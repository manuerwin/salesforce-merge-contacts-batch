/**
 * Created by Manu Erwin April 2023
 * @description Batch Apex:
 * - Create JSON snapshot of Contact and related ACR info as custom “Contact Snapshot”,
 * - Merge non-surviving records,
 * - Re-create ACR’s as needed.
 *
 * Dependencies: NebulaLogger https://github.com/jongpie/NebulaLogger
 *
 */
public class ContactMergeBatch implements Database.Batchable<sObject> {
  private String originalTransactionId;
  public Map<String, Schema.SObjectField> contactFields;
  public Map<String, Schema.SObjectField> acrFields;

  /**
   * @description constructor - obtain Contact and ACR schema fields
   */
  public ContactMergeBatch() {
    this.contactFields = Schema.SObjectType.Contact.fields.getMap();
    this.acrFields = Schema.SObjectType.AccountContactRelation.fields.getMap();
    this.originalTransactionId = Logger.getTransactionId();
  }

  /**
   * @description batch start
   * @param bc BatchableContext
   * @return Database.QueryLocator of contacts where "Should Merge" and "Is Survivor" fields are true and "Dedupe Key" is populated, including a sub query for the related ACR’s
   */
  public Database.QueryLocator start(Database.BatchableContext bc) {
    String query = contactAllFieldsQuery();
    String acrQuery = acrAllFieldsQuery();
    query += ', ' + acrQuery;
    query += ' FROM Contact WHERE Should_Merge__c = true AND Is_Survivor__c = true AND Dedupe_Key__c != NULL';
    return Database.getQueryLocator(query);
  }

  /**
   * @description batch execution
   * @param bc BatchableContext
   * @param scope : list of records to be processed
   */
  public void execute(Database.BatchableContext bc, List<sObject> scope) {
    Logger.setParentLogTransactionId(this.originalTransactionId);
    Logger.info('Starting ContactMergeBatch.execute');
    List<Contact_Snapshot__c> contactSnapshotList = new List<Contact_Snapshot__c>();
    Set<String> dedupeKeySet = new Set<String>();
    Logger.info('Assumption: there is only one Survivor per dedupe Key');
    Map<String, Contact> dedupeKeySurvivorMap = new Map<String, Contact>();

    for (sObject obj : scope) {
      Contact originalContact = (Contact) obj;
      dedupeKeySet.add(originalContact.Dedupe_Key__c);
      contactSnapshotList.add(generateSnapshotRecord(originalContact)); // snapshot of all Survivors
      if (!dedupeKeySurvivorMap.containsKey(originalContact.Dedupe_Key__c)) {
        dedupeKeySurvivorMap.put(
          originalContact.Dedupe_Key__c,
          originalContact
        );
      }
      Logger.debug(
        'Process Survivor contact with dedupe key: ' +
        originalContact.Dedupe_Key__c,
        scope
      );
    }

    // Get all non-surviving contacts plus related ACR’s for the provided dedupe keys
    String query = contactAllFieldsQuery();
    String acrQuery = acrAllFieldsQuery();
    query += ', ' + acrQuery;

    // expand the dedupe keys into a query string
    String dedupeKeyQueryString = '(';
    for (String dedupeKey : dedupeKeySet) {
      dedupeKeyQueryString += '\'' + dedupeKey + '\', ';
    }
    dedupeKeyQueryString = dedupeKeyQueryString.substring(
      0,
      dedupeKeyQueryString.length() - 2
    );
    dedupeKeyQueryString += ')';

    query +=
      ' FROM Contact WHERE Should_Merge__c = true AND Is_Survivor__c = false AND Dedupe_Key__c IN ' +
      dedupeKeyQueryString;

    List<Contact> nonsurvivorContactsList = Database.query(query);

    if (!nonsurvivorContactsList.isEmpty()) {
      Logger.info('## non-survivors exist for survivor contacts');
      // generate snapshots and map of non-surviving contacts
      List<AccountContactRelation> acrsToRecreate = new List<AccountContactRelation>();
      Map<String, List<Contact>> keyNonSurvivorContactsMap = new Map<String, List<Contact>>();
      for (Contact con : nonsurvivorContactsList) {
        contactSnapshotList.add(generateSnapshotRecord(con));

        // Create a map of dedupe key and non surviving contacts
        if (!keyNonSurvivorContactsMap.containsKey(con.Dedupe_Key__c)) {
          keyNonSurvivorContactsMap.put(con.Dedupe_Key__c, new List<Contact>());
        }
        keyNonSurvivorContactsMap.get(con.Dedupe_Key__c).add(con);

        // Recreate acrs where the Account is different from the surviving Contact's Account
        List<AccountContactRelation> originalDupeACRs = con.AccountContactRelations.deepClone();
        for (AccountContactRelation acr : originalDupeACRs) {
          Contact survivorContact = dedupeKeySurvivorMap.get(con.Dedupe_Key__c);
          if (acr.AccountId != survivorContact.AccountId) {
            acr.ContactId = survivorContact.Id;
            acr.Account_Contact_Id__c =
              con.AccountId +
              '|' +
              survivorContact.Id;
            acrsToRecreate.add(acr);
          }
        }
      }

      // upsert snapshots
      if (contactSnapshotList.size() > 0) {
        Logger.info('## about to upsert contact snapshots');
        Logger.debug('## contact snapshots: ' + contactSnapshotList);
        Schema.SObjectField uniqueKey = Contact_Snapshot__c.Fields.Unique_Key__c;
        List<Database.UpsertResult> snapshotUpsertResults = Database.upsert(
          contactSnapshotList,
          uniqueKey,
          false
        );

        for (Database.UpsertResult res : snapshotUpsertResults) {
          if (!res.isSuccess()) {
            for (Database.Error err : res.getErrors()) {
              Logger.error(
                '##DEBUG: contact_snapshot upsert error: ' +
                  res.getId() +
                  err.getMessage()
              );
            }
          } else {
            Logger.info('Created Contact Snapshot: ' + res);
          }
        }
      }

      // Merge duplicates
      List<Database.MergeResult> contactMergeResults = new List<Database.MergeResult>();
      for (String dedupeKey : dedupeKeySurvivorMap.keySet()) {
        Contact survivorContactFromMap = dedupeKeySurvivorMap.get(dedupeKey);
        Contact survivorContact = new Contact(
          Id = survivorContactFromMap.Id,
          FirstName = survivorContactFromMap.FirstName,
          LastName = survivorContactFromMap.LastName
        );

        if (keyNonSurvivorContactsMap.containsKey(dedupeKey)) {
          List<Contact> duplicates = keyNonSurvivorContactsMap.get(dedupeKey);
          Integer numberOfDupes = duplicates.size();

          while (numberOfDupes > 0) {
            List<Contact> contactsToMerge = new List<Contact>();
            if (numberOfDupes >= 2) {
              // pull two from the collection for processing
              for (Integer count = 0; count < 2; count++) {
                Contact firstCon = generateSimpleContact(duplicates.remove(0));
                contactsToMerge.add(firstCon);
              }
            } else {
              Contact firstCon = generateSimpleContact(duplicates.remove(0));
              contactsToMerge.add(firstCon);
            }
            Logger.debug(
              '## about to merge duplicate contacts: ' + contactsToMerge
            );
            Database.MergeResult[] contactMergeResult = Database.merge(
              survivorContact,
              contactsToMerge,
              false
            );
            for (Database.MergeResult res : contactMergeResult) {
              contactMergeResults.add(res);
            }
            numberOfDupes = duplicates.size();
          }
        }
      }

      for (Database.MergeResult res : contactMergeResults) {
        if (!res.isSuccess()) {
          for (Database.Error err : res.getErrors()) {
            Logger.error(
              '##DEBUG: contact merge error: ' +
                res.getId() +
                ' : ' +
                err.getMessage()
            );
          }
        } else {
          Logger.debug('Merged Contacts: ' + res);
        }
      }

      // recreate ACR's for non-surviving Contacts
      if (acrsToRecreate.size() > 0) {
        Logger.info('## about to recreate ACRs');
        Logger.debug('## ACRs: ' + acrsToRecreate);
        Schema.SObjectField uniqueKey = AccountContactRelation.Fields.Account_Contact_Id__c;
        List<Database.SaveResult> acrSaveResults = Database.insert(
          acrsToRecreate,
          false
        );

        for (Database.SaveResult res : acrSaveResults) {
          if (!res.isSuccess()) {
            for (Database.Error err : res.getErrors()) {
              Logger.error(
                '##DEBUG: ACR insert error: ' +
                  res.getId() +
                  ' : ' +
                  err.getMessage()
              );
            }
          } else {
            Logger.info('Recreated ACR: ' + res);
          }
        }
      }
    }
    Logger.saveLog();
  }

  /**
   * @description batch optional processing logic if needed
   * @param bc BatchableContext
   */
  public void finish(Database.BatchableContext bc) {
    Logger.setParentLogTransactionId(this.originalTransactionId);
    Logger.info('Finishing running ContactMergeBatch');
    Logger.saveLog();
  }

  /**
   * @description Method to generate a query string of all contact fields
   * @return query = string of all contact fields
   */
  public String contactAllFieldsQuery() {
    String query = 'SELECT ';
    for (String fieldName : contactFields.keySet()) {
      query += fieldName + ', ';
    }
    query = query.substring(0, query.length() - 2);

    return query;
  }

  /**
   * @description Method to generate a query string of all account contact relation fields
   * @return Query = string of all ACR fields
   */
  public String acrAllFieldsQuery() {
    String query = '(SELECT ';
    for (String fieldName : acrFields.keySet()) {
      query += fieldName + ', ';
    }
    query = query.substring(0, query.length() - 2);
    query += ' FROM AccountContactRelations)';

    return query;
  }

  /**
   * @description Method to generate a contact snapshot record, given a contact;
   * @param contactToSerialise = Contact record
   * @return snapshot = Contact_Snapshot record
   */
  private Contact_Snapshot__c generateSnapshotRecord(
    Contact contactToSerialise
  ) {
    String jsonBody = (contactToSerialise != null)
      ? JSON.serializePretty(contactToSerialise)
      : null;
    Contact_Snapshot__c snapshot = new Contact_Snapshot__c(
      Contact__c = contactToSerialise.Id,
      Direct_Account_Id__c = contactToSerialise.AccountId,
      Snapshot_Date_Time__c = system.now(),
      Unique_Key__c = String.valueOf(contactToSerialise.Id) +
        '|' +
        String.valueOf(contactToSerialise.AccountId),
      Contact_Information__c = jsonBody
    );

    return snapshot;
  }

  /**
   * @description Method to generate a simple contact for merging
   * @param contactToSimplify = Contact record
   * @return simpleContact = Contact record with few fields
   */
  private Contact generateSimpleContact(Contact contactToSimplify) {
    Contact simpleContact = new Contact(
      Id = contactToSimplify.Id,
      FirstName = contactToSimplify.FirstName,
      LastName = contactToSimplify.LastName
    );
    return simpleContact;
  }
}
