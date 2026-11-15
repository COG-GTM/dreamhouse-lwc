@isTest
private with sharing class FileUtilitiesTest {
    @isTest
    static void createFileSucceedsWhenCorrectInput() {
        // GIVEN
        Property__c property = new Property__c();
        insert property;

        String base64Data = '/9j/4AAQSkZJRgABAQAAAQABAAD/4gHYSUNDX1BST0ZJTEUAAQEAAAHIAAAAAAQwAABtbnRyUkdCIFhZWiAAAAAAAAAAAAAAAABhY3NwAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAQAA9tYAAQAAAADTLQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAlkZXNjAAAA8AAAACRyWFlaAAABFAAAABRnWFlaAAABKAAAABRiWFlaAAABPAAAABR3dHB0AAABUAAAABRyVFJDAAABZAAAAChnVFJDAAABZAAAAChiVFJDAAABZAAAAChjcHJ0AAABjAAAADxtbHVjAAAAAAAAAAEAAAAMZW5VUwAAAAgAAAAcAHMAUgBHAEJYWVogAAAAAAAAb6IAADj1AAADkFhZWiAAAAAAAABimQAAt4UAABjaWFlaIAAAAAAAACSgAAAPhAAAts9YWVogAAAAAAAA9tYAAQAAAADTLXBhcmEAAAAAAAQAAAACZmYAAPKnAAANWQAAE9AAAApbAAAAAAAAAABtbHVjAAAAAAAAAAEAAAAMZW5VUwAAACAAAAAcAEcAbwBvAGcAbABlACAASQBuAGMALgAgADIAMAAxADb';
        String fileName = 'file.png';
        String recordId = property.Id;

        // WHEN
        String contentDocumentLinkId = FileUtilities.createFile(
            base64Data,
            fileName,
            recordId
        );

        // THEN
        Assert.isNotNull(contentDocumentLinkId);
    }

    @isTest
    static void createFileFailsWhenIncorrectRecordId() {
        // GIVEN
        String base64Data = '/9j/4AAQSkZJRgABAQAAAQABAAD/4gHYSUNDX1BST0ZJTEUAAQEAAAHIAAAAAAQwAABtbnRyUkdCIFhZWiAAAAAAAAAAAAAAAABhY3NwAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAQAA9tYAAQAAAADTLQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAlkZXNjAAAA8AAAACRyWFlaAAABFAAAABRnWFlaAAABKAAAABRiWFlaAAABPAAAABR3dHB0AAABUAAAABRyVFJDAAABZAAAAChnVFJDAAABZAAAAChiVFJDAAABZAAAAChjcHJ0AAABjAAAADxtbHVjAAAAAAAAAAEAAAAMZW5VUwAAAAgAAAAcAHMAUgBHAEJYWVogAAAAAAAAb6IAADj1AAADkFhZWiAAAAAAAABimQAAt4UAABjaWFlaIAAAAAAAACSgAAAPhAAAts9YWVogAAAAAAAA9tYAAQAAAADTLXBhcmEAAAAAAAQAAAACZmYAAPKnAAANWQAAE9AAAApbAAAAAAAAAABtbHVjAAAAAAAAAAEAAAAMZW5VUwAAACAAAAAcAEcAbwBvAGcAbABlACAASQBuAGMALgAgADIAMAAxADb';
        String fileName = 'file.png';
        String recordId = 'INVALID_ID';

        try {
            // WHEN
            String contentDocumentLinkId = FileUtilities.createFile(
                base64Data,
                fileName,
                recordId
            );
            Assert.fail('Expected an AuraHandledException');
        } catch (Exception e) {
            // THEN
            Assert.isInstanceOfType(e, AuraHandledException.class);
        }
    }

    @isTest
    static void createFileFailsWhenIncorrectBase64Data() {
        // GIVEN
        Property__c property = new Property__c();
        insert property;

        String base64Data = '';
        String fileName = 'file.png';
        String recordId = property.Id;

        try {
            // WHEN
            String contentDocumentLinkId = FileUtilities.createFile(
                base64Data,
                fileName,
                recordId
            );
            Assert.fail('Expected an AuraHandledException');
        } catch (Exception e) {
            // THEN
            Assert.isInstanceOfType(e, AuraHandledException.class);
        }
    }

    @isTest
    static void createFileFailsWhenIncorrectFilename() {
        // GIVEN
        Property__c property = new Property__c();
        insert property;

        String base64Data = '/9j/4AAQSkZJRgABAQAAAQABAAD/4gHYSUNDX1BST0ZJTEUAAQEAAAHIAAAAAAQwAABtbnRyUkdCIFhZWiAAAAAAAAAAAAAAAABhY3NwAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAQAA9tYAAQAAAADTLQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAlkZXNjAAAA8AAAACRyWFlaAAABFAAAABRnWFlaAAABKAAAABRiWFlaAAABPAAAABR3dHB0AAABUAAAABRyVFJDAAABZAAAAChnVFJDAAABZAAAAChiVFJDAAABZAAAAChjcHJ0AAABjAAAADxtbHVjAAAAAAAAAAEAAAAMZW5VUwAAAAgAAAAcAHMAUgBHAEJYWVogAAAAAAAAb6IAADj1AAADkFhZWiAAAAAAAABimQAAt4UAABjaWFlaIAAAAAAAACSgAAAPhAAAts9YWVogAAAAAAAA9tYAAQAAAADTLXBhcmEAAAAAAAQAAAACZmYAAPKnAAANWQAAE9AAAApbAAAAAAAAAABtbHVjAAAAAAAAAAEAAAAMZW5VUwAAACAAAAAcAEcAbwBvAGcAbABlACAASQBuAGMALgAgADIAMAAxADb';
        String fileName = '';
        String recordId = property.Id;

        try {
            // WHEN
            String contentDocumentLinkId = FileUtilities.createFile(
                base64Data,
                fileName,
                recordId
            );
            Assert.fail('Expected an AuraHandledException');
        } catch (Exception e) {
            // THEN
            Assert.isInstanceOfType(e, AuraHandledException.class);
        }
    }

    @isTest
    static void createFileStoresContentAndLinksItToRecord() {
        // GIVEN
        Property__c property = new Property__c();
        insert property;

        Blob fileContent = Blob.valueOf('Dreamhouse test file');
        String base64Data = EncodingUtil.base64Encode(fileContent);
        String fileName = 'floorplan.txt';

        // WHEN
        Test.startTest();
        String contentDocumentLinkId = FileUtilities.createFile(
            base64Data,
            fileName,
            property.Id
        );
        Test.stopTest();

        // THEN
        ContentDocumentLink link = [
            SELECT ContentDocumentId, LinkedEntityId, ShareType
            FROM ContentDocumentLink
            WHERE Id = :contentDocumentLinkId
        ];
        Assert.areEqual(property.Id, link.LinkedEntityId);
        Assert.areEqual('V', link.ShareType);

        ContentVersion version = [
            SELECT Title, PathOnClient, VersionData
            FROM ContentVersion
            WHERE ContentDocumentId = :link.ContentDocumentId
        ];
        Assert.areEqual(fileName, version.Title);
        Assert.areEqual(fileName, version.PathOnClient);
        Assert.areEqual(fileContent.toString(), version.VersionData.toString());
    }

    @isTest
    static void createFileCreatesSeparateDocumentsForEachUpload() {
        // GIVEN
        Property__c property = new Property__c();
        insert property;

        String base64Data = EncodingUtil.base64Encode(
            Blob.valueOf('Dreamhouse test file')
        );

        // WHEN
        Test.startTest();
        String firstLinkId = FileUtilities.createFile(
            base64Data,
            'first.txt',
            property.Id
        );
        String secondLinkId = FileUtilities.createFile(
            base64Data,
            'second.txt',
            property.Id
        );
        Test.stopTest();

        // THEN
        Assert.areNotEqual(firstLinkId, secondLinkId);
        List<ContentDocumentLink> links = [
            SELECT ContentDocumentId
            FROM ContentDocumentLink
            WHERE LinkedEntityId = :property.Id
        ];
        Assert.areEqual(2, links.size());
        Assert.areNotEqual(
            links[0].ContentDocumentId,
            links[1].ContentDocumentId
        );
    }

    @isTest
    static void createFileFailsWhenRecordIdIsNull() {
        // GIVEN
        String base64Data = EncodingUtil.base64Encode(
            Blob.valueOf('Dreamhouse test file')
        );

        try {
            // WHEN
            FileUtilities.createFile(base64Data, 'file.txt', null);
            Assert.fail('Expected an AuraHandledException');
        } catch (Exception e) {
            // THEN
            Assert.isInstanceOfType(e, AuraHandledException.class);
        }
    }

    @isTest
    static void createFileFailsWhenBase64DataIsNull() {
        // GIVEN
        Property__c property = new Property__c();
        insert property;

        try {
            // WHEN
            FileUtilities.createFile(null, 'file.txt', property.Id);
            Assert.fail('Expected an AuraHandledException');
        } catch (Exception e) {
            // THEN
            Assert.isInstanceOfType(e, AuraHandledException.class);
        }

        Assert.areEqual(
            0,
            [
                SELECT COUNT()
                FROM ContentDocumentLink
                WHERE LinkedEntityId = :property.Id
            ]
        );
    }
}
