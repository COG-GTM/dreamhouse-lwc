public with sharing class FileUtilities {
    @AuraEnabled
    public static String createFile(
        String base64data,
        String filename,
        String recordId
    ) {
        Savepoint savepoint = Database.setSavepoint();
        try {
            return insertFileAndLink(base64data, filename, recordId);
        } catch (Exception e) {
            Database.rollback(savepoint);
            throw e;
        }
    }

    private static String insertFileAndLink(
        String base64data,
        String filename,
        String recordId
    ) {
        try {
            ContentVersion contentVersion = new ContentVersion();
            contentVersion.VersionData = EncodingUtil.base64Decode(base64data);
            contentVersion.Title = filename;
            contentVersion.PathOnClient = filename;
            insert contentVersion;

            contentVersion = [
                SELECT ContentDocumentId
                FROM ContentVersion
                WHERE Id = :contentVersion.Id
                WITH USER_MODE
            ];

            ContentDocumentLink contentDocumentLink = new ContentDocumentLink();
            contentDocumentLink.ContentDocumentId = contentVersion.ContentDocumentId;
            contentDocumentLink.LinkedEntityId = recordId;
            contentDocumentLink.ShareType = 'V';
            insert contentDocumentLink;

            return contentDocumentLink.Id;
        } catch (Exception e) {
            throw new AuraHandledException('Error creating file: ' + e);
        }
    }
}
