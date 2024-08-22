@IsTest
private class ContactMergeBatchTest {
  @TestSetup
  static void setup() {
    List<Account> accounts = new List<Account>();
    Account alphaAccount = new Account(Name = 'Alpha Testing');
    Account betaAccount = new Account(Name = 'Beta Testing');
    Account charlieAccount = new Account(Name = 'Charlie Testing');
    Account deltaAccount = new Account(Name = 'Delta Testing');
    accounts.add(alphaAccount);
    accounts.add(betaAccount);
    accounts.add(charlieAccount);
    accounts.add(deltaAccount);
    insert accounts;
    System.debug('##DEBUG##: insert accounts ' + accounts);

    List<Contact> survivorContacts = new List<Contact>();
    // survivor contacts with duplicates
    Contact amandaSurvivorContact = new Contact(
      FirstName = 'amanda alpha',
      LastName = 'Survivor',
      Should_Merge__c = true,
      Is_Survivor__c = true,
      Dedupe_Key__c = 'amanda',
      AccountId = alphaAccount.Id
    );
    survivorContacts.add(amandaSurvivorContact);
    Contact benSurvivorContact = new Contact(
      FirstName = 'ben beta',
      LastName = 'Survivor',
      Should_Merge__c = true,
      Is_Survivor__c = true,
      Dedupe_Key__c = 'ben',
      AccountId = betaAccount.Id
    );
    survivorContacts.add(benSurvivorContact);
    Contact charlieSurvivorContact = new Contact(
      FirstName = 'charlie charlie',
      LastName = 'Survivor',
      Should_Merge__c = true,
      Is_Survivor__c = true,
      Dedupe_Key__c = 'charlie',
      AccountId = charlieAccount.Id
    );
    survivorContacts.add(charlieSurvivorContact);

    // survivor contact with no duplicates
    Contact daniSurvivorContact = new Contact(
      FirstName = 'dani delta',
      LastName = 'Survivor',
      Should_Merge__c = true,
      Is_Survivor__c = true,
      Dedupe_Key__c = 'dani',
      AccountId = alphaAccount.Id
    );
    survivorContacts.add(daniSurvivorContact);

    insert survivorContacts;
    System.debug('##DEBUG##: insert survivorContacts ' + survivorContacts);

    // non-surviving contacts at the same account as the survivors (3 amandas to check the merge loop of 2)
    List<Contact> nonSurvivorContacts = new List<Contact>();
    Contact amanda2Dupe = new Contact(
      FirstName = 'amanda2 alpha',
      LastName = 'Doe',
      Should_Merge__c = true,
      Is_Survivor__c = false,
      Dedupe_Key__c = 'amanda',
      AccountId = alphaAccount.Id
    );
    nonSurvivorContacts.add(amanda2Dupe);
    Contact amanda3Dupe = new Contact(
      FirstName = 'amanda3 alpha',
      LastName = 'Doe',
      Should_Merge__c = true,
      Is_Survivor__c = false,
      Dedupe_Key__c = 'amanda',
      AccountId = alphaAccount.Id
    );
    nonSurvivorContacts.add(amanda3Dupe);
    Contact amanda4Dupe = new Contact(
      FirstName = 'amanda4 alpha',
      LastName = 'Doe',
      Should_Merge__c = true,
      Is_Survivor__c = false,
      Dedupe_Key__c = 'amanda',
      AccountId = alphaAccount.Id
    );
    nonSurvivorContacts.add(amanda4Dupe);
    Contact ben2Dupe = new Contact(
      FirstName = 'ben2 beta',
      LastName = 'Doe',
      Should_Merge__c = true,
      Is_Survivor__c = false,
      Dedupe_Key__c = 'ben',
      AccountId = betaAccount.Id
    );
    nonSurvivorContacts.add(ben2Dupe);

    // non-surviving contacts with ACR's to different accounts
    Contact amanda5Dupe = new Contact(
      FirstName = 'amanda5 alpha against beta',
      LastName = 'Doe',
      Should_Merge__c = true,
      Is_Survivor__c = false,
      Dedupe_Key__c = 'amanda',
      AccountId = betaAccount.Id
    );
    nonSurvivorContacts.add(amanda5Dupe);
    Contact ben3Dupe = new Contact(
      FirstName = 'ben3 beta against delta',
      LastName = 'Doe',
      Should_Merge__c = true,
      Is_Survivor__c = false,
      Dedupe_Key__c = 'ben',
      AccountId = deltaAccount.Id
    );
    nonSurvivorContacts.add(ben3Dupe);
    Contact charlie2Dupe = new Contact(
      FirstName = 'charlie2 charlie against delta',
      LastName = 'Doe',
      Should_Merge__c = true,
      Is_Survivor__c = false,
      Dedupe_Key__c = 'charlie',
      AccountId = deltaAccount.Id
    );
    nonSurvivorContacts.add(charlie2Dupe);
    insert nonSurvivorContacts;
    System.debug(
      '##DEBUG##: insert nonSurvivorContacts ' + nonSurvivorContacts
    );

    // stretch: bulk creation of data to test governor limits/bulkification of the batch apex
  }

  @IsTest
  static void testContactMergeBatch() {
    Test.startTest();
    ContactMergeBatch batch = new ContactMergeBatch();
    Database.executeBatch(batch);
    Test.stopTest();

    // Verify contact snapshots were created
    List<Contact_Snapshot__c> expectedContactSnapshots = [
      SELECT Id
      FROM Contact_Snapshot__c
    ];
    System.assertEquals(
      11,
      expectedContactSnapshots.size(),
      'There should be 11 snapshots'
    );

    // Verify that duplicate contacts were merged with original contacts
    List<Contact> expectedContactsAlpha = [
      SELECT Id, FirstName, LastName, Dedupe_Key__c, AccountId
      FROM Contact
      WHERE Dedupe_Key__c = 'amanda'
    ];
    System.assertEquals(
      1,
      expectedContactsAlpha.size(),
      'There should only be one alpha contact'
    );
    List<Contact> expectedContactsBeta = [
      SELECT Id, FirstName, LastName, Dedupe_Key__c, AccountId
      FROM Contact
      WHERE Dedupe_Key__c = 'ben'
    ];
    System.assertEquals(
      1,
      expectedContactsBeta.size(),
      'There should only be one beta contact'
    );
    List<Contact> expectedContactsCharlie = [
      SELECT Id, FirstName, LastName, Dedupe_Key__c, AccountId
      FROM Contact
      WHERE Dedupe_Key__c = 'charlie'
    ];
    System.assertEquals(
      1,
      expectedContactsCharlie.size(),
      'There should only be one charlie contact'
    );
    List<Contact> expectedContactsDelta = [
      SELECT Id, FirstName, LastName, Dedupe_Key__c, AccountId
      FROM Contact
      WHERE Dedupe_Key__c = 'dani'
    ];
    System.assertEquals(
      1,
      expectedContactsDelta.size(),
      'The delta contact should be untouched'
    );

    // Verify that duplicate contacts were deleted
    List<Contact> duplicateContacts = [
      SELECT Id
      FROM Contact
      WHERE Should_Merge__c = TRUE AND Is_Survivor__c = FALSE
    ];
    System.assertEquals(
      0,
      duplicateContacts.size(),
      'Duplicate contacts should have been deleted'
    );

    // Verify that ACR's exist after merging
    List<AccountContactRelation> alphaSurvivorACRs = [
      SELECT Id
      FROM AccountContactRelation
      WHERE Contact.Dedupe_Key__c = 'amanda'
    ];
    System.assertEquals(
      2,
      alphaSurvivorACRs.size(),
      'There should be 2 ACRs for alpha'
    );
    List<AccountContactRelation> betaSurvivorACRs = [
      SELECT Id
      FROM AccountContactRelation
      WHERE Contact.Dedupe_Key__c = 'ben'
    ];
    System.assertEquals(
      2,
      betaSurvivorACRs.size(),
      'There should be 2 ACRs for: beta'
    );
    List<AccountContactRelation> charlieSurvivorACRs = [
      SELECT Id
      FROM AccountContactRelation
      WHERE Contact.Dedupe_Key__c = 'charlie'
    ];
    System.assertEquals(
      2,
      charlieSurvivorACRs.size(),
      'There should be 2 ACRs for: charlie'
    );
  }
}
