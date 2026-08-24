public with sharing class SampleDataController {
    @AuraEnabled
    public static void importSampleData() {
        try {
            deleteSampleData();
            insertBrokers();
            insertProperties();
            insertContacts();
        } catch (Exception e) {
            throw new AuraHandledException(
                'Failed to import sample data: ' + e.getMessage()
            );
        }
    }

    private static void deleteSampleData() {
        Database.delete(
            [SELECT Id FROM Case WITH USER_MODE],
            AccessLevel.USER_MODE
        );
        Database.delete(
            [SELECT Id FROM Property__c WITH USER_MODE],
            AccessLevel.USER_MODE
        );
        Database.delete(
            [SELECT Id FROM Broker__c WITH USER_MODE],
            AccessLevel.USER_MODE
        );
        Database.delete(
            [SELECT Id FROM Contact WITH USER_MODE],
            AccessLevel.USER_MODE
        );
    }

    private static void insertBrokers() {
        StaticResource brokersResource = [
            SELECT Id, Body
            FROM StaticResource
            WHERE Name = 'sample_data_brokers'
            WITH USER_MODE
        ];
        String brokersJSON = brokersResource.body.toString();
        List<Broker__c> brokers = (List<Broker__c>) JSON.deserialize(
            brokersJSON,
            List<Broker__c>.class
        );
        Database.insert(brokers, AccessLevel.USER_MODE);
    }

    private static void insertProperties() {
        StaticResource propertiesResource = [
            SELECT Id, Body
            FROM StaticResource
            WHERE Name = 'sample_data_properties'
            WITH USER_MODE
        ];
        String propertiesJSON = propertiesResource.body.toString();
        List<Property__c> properties = (List<Property__c>) JSON.deserialize(
            propertiesJSON,
            List<Property__c>.class
        );
        randomizeDateListed(properties);
        Database.insert(properties, AccessLevel.USER_MODE);
    }

    private static void insertContacts() {
        StaticResource contactsResource = [
            SELECT Id, Body
            FROM StaticResource
            WHERE Name = 'sample_data_contacts'
            WITH USER_MODE
        ];
        String contactsJSON = contactsResource.body.toString();
        List<Contact> contacts = (List<Contact>) JSON.deserialize(
            contactsJSON,
            List<Contact>.class
        );
        Database.insert(contacts, AccessLevel.USER_MODE);
    }

    private static void randomizeDateListed(List<Property__c> properties) {
        for (Property__c property : properties) {
            property.Date_Listed__c =
                System.today() - Integer.valueof((Math.random() * 90));
        }
    }
}
