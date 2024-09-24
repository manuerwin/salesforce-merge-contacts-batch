// Use .apex files to store anonymous Apex.
// You can execute anonymous Apex in VS Code by selecting the
//     apex text and running the command:
//     SFDX: Execute Anonymous Apex with Currently Selected Text
// You can also execute the entire file by running the command:
//     SFDX: Execute Anonymous Apex with Editor Contents

// Select and run the TestSetup code via ExecAnon to create records

// Running the code in smaller batches to avoid TOO MANY SOQL's
Database.executeBatch(new ContactMergeBatch(), 10);