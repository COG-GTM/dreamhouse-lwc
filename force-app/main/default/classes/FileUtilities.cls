public with sharing class FileUtilities {
    @AuraEnabled
    public static String createFile(
        String base64data,
        String filename,
        String recordId
    ) {
        try {
            ContentVersion contentVersion = new ContentVersion();
            contentVersion.VersionData = EncodingUtil.base64Decode(base64data);
            contentVersion.Title = filename;
            contentVersion.PathOnClient = filename;
            Database.insert(contentVersion, AccessLevel.USER_MODE);

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
            Database.insert(contentDocumentLink, AccessLevel.USER_MODE);

            return contentDocumentLink.Id;
        } catch (Exception e) {
            String errorMessage = 'Error creating file: ' + e.getMessage();
            AuraHandledException error = new AuraHandledException(errorMessage);
            error.setMessage(errorMessage);
            throw error;
        }
    }
}
