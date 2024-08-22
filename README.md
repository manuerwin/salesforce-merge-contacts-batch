# salesforce-merge-contacts-batch

# What does this do?

Batch Apex to merge Salesforce Contact records in Salesforce.

# Who is this for?

Salesforce System Administrators.

# When do I use this?

When you don't have access to [Duplicate Jobs](https://help.salesforce.com/s/articleView?id=sf.duplicate_jobs.htm&type=5), you need to merge many duplicate contacts, and it would take too long manually via the browser.

# How does the code work?

Batch Apex does the heavy lifting for us, with initial snapshots of Contact records as child “Contact Snapshot”, then merging non-surviving records, then recreating ACR’s as needed.

1. Queries all Contacts where:
   - Dedupe Key has a value
   - Is Survivor is either TRUE or FALSE, and
   - Should Merge is TRUE
2. Creates child custom Contact Snapshot records for each of the above Contacts
3. Merges non-surviving contacts (Is Survivor = FALSE) with their survivor contact (Is Survivor = TRUE) based on the same Dedupe Key value.
4. Recreates ACR’s (Account Contact Relationships) as needed

# How do I merge duplicate contacts?

## 0) Install and enable

### install the amazing Nebula Logger (unlocked version)

https://github.com/jongpie/NebulaLogger

### enable Contacts to Multiple Accounts

https://help.salesforce.com/s/articleView?id=sf.shared_contacts_set_up.htm&type=5

### deploy package.xml to your org

## 1) Backup your data!

## 2) Prepare your duplicate contacts

Bulk update the Contacts you will be merging as follows:

**Survivor Contacts**

- Set Dedupe Key field with a unique value for each surviving Contact, for example, 350a7fda-0e69-4477
- Set Is Survivor to TRUE, so the code knows this record should survive
- Set Should Merge to TRUE

**Non-survivor Contacts (could be many for each survivor)**

- Set Dedupe Key field with the same unique value as the surviving Contact, for example, 350a7fda-0e69-4477
- Set Is Survivor to FALSE, so the code knows these records should be merged
- Set Should Merge to TRUE

## 3) Add yourself to Nebula Logger logs

In Salesforce, open the Logger Console app, navigate to Logger Settings, and add yourself to Logs.

## 4) Run the merge code

Run in small batches via Execute Anonymous.

    // Run the code in smaller batches to avoid TOO MANY SOQL's
    ContactMergeBatch batch = new ContactMergeBatch();
    Database.executeBatch(batch, 10);

## 5) Review logs for errors

You will need to review all the Logs and child Log Entries to see if any records didn’t process or need further processing.

### Example errors:

> “A direct relationship can't be deleted. You can modify the relationship by changing the contact's parent account or deleting the contact.”

Just what it says in the error, the relationship needs to be changed to not direct before the contact can be merged

> “##DEBUG: contact merge error: 0032x0000070erxAAA : These contacts have the same related account. Open the related account record and remove redundant account–contact relationships. Then try merging again.”

The non-survivor has a relationship (ACR) to the same account as the survivor, this ACR needs to be deleted before the non-survivor can be merged

> “##DEBUG: ACR insert error: null : This contact already has a relationship with this account.”

The code is trying to recreate an ACR that already exists, can be ignored as the surviving contact already has a relationship with the account

## 6) Remove contacts from further processing

After all merging is successful, perform another data update of the surviving Contacts to set “Should Merge” to FALSE so they will be ignored by the code in future.
