/**
 * Imports the Dreamhouse sample data without touching existing records: a
 * sample record that already exists (matched by its natural key) is skipped,
 * and nothing is ever updated or deleted, so the import is safe in a shared org.
 */
public with sharing class SampleDataController {
    @AuraEnabled
    public static void importSampleData() {
        Map<Decimal, Id> brokerIdsBySampleId = insertMissingBrokers();
        insertMissingProperties(brokerIdsBySampleId);
        insertMissingContacts();
    }

    private static Map<Decimal, Id> insertMissingBrokers() {
        List<Broker__c> sampleBrokers = (List<Broker__c>) loadSampleData(
            'sample_data_brokers',
            List<Broker__c>.class
        );

        Set<Decimal> sampleIds = new Set<Decimal>();
        Set<String> emails = new Set<String>();
        for (Broker__c broker : sampleBrokers) {
            sampleIds.add(broker.Broker_Id__c);
            emails.add(broker.Email__c);
        }

        Map<Decimal, Id> existingIdsBySampleId = new Map<Decimal, Id>();
        Map<String, Id> existingIdsByEmail = new Map<String, Id>();
        for (Broker__c existing : [
            SELECT Id, Broker_Id__c, Email__c
            FROM Broker__c
            WHERE Broker_Id__c IN :sampleIds OR Email__c IN :emails
            ORDER BY CreatedDate
        ]) {
            if (
                existing.Broker_Id__c != null &&
                !existingIdsBySampleId.containsKey(existing.Broker_Id__c)
            ) {
                existingIdsBySampleId.put(existing.Broker_Id__c, existing.Id);
            }
            String emailKey = normalize(existing.Email__c);
            if (emailKey != null && !existingIdsByEmail.containsKey(emailKey)) {
                existingIdsByEmail.put(emailKey, existing.Id);
            }
        }

        Map<Decimal, Id> brokerIdsBySampleId = new Map<Decimal, Id>();
        List<Broker__c> brokersToInsert = new List<Broker__c>();
        for (Broker__c broker : sampleBrokers) {
            Id existingId = existingIdsBySampleId.get(broker.Broker_Id__c);
            if (existingId == null) {
                existingId = existingIdsByEmail.get(normalize(broker.Email__c));
            }
            if (existingId != null) {
                brokerIdsBySampleId.put(broker.Broker_Id__c, existingId);
            } else {
                brokersToInsert.add(broker);
            }
        }
        insert brokersToInsert;
        for (Broker__c broker : brokersToInsert) {
            brokerIdsBySampleId.put(broker.Broker_Id__c, broker.Id);
        }
        return brokerIdsBySampleId;
    }

    private static void insertMissingProperties(
        Map<Decimal, Id> brokerIdsBySampleId
    ) {
        List<Property__c> sampleProperties = (List<Property__c>) loadSampleData(
            'sample_data_properties',
            List<Property__c>.class
        );

        Set<String> names = new Set<String>();
        for (Property__c property : sampleProperties) {
            names.add(property.Name);
        }
        Set<String> existingKeys = new Set<String>();
        for (Property__c existing : [
            SELECT Name, Address__c
            FROM Property__c
            WHERE Name IN :names
        ]) {
            existingKeys.add(propertyKey(existing));
        }

        List<Property__c> propertiesToInsert = new List<Property__c>();
        for (Property__c property : sampleProperties) {
            if (existingKeys.contains(propertyKey(property))) {
                continue;
            }
            if (property.Broker__r != null) {
                property.Broker__c = brokerIdsBySampleId.get(
                    property.Broker__r.Broker_Id__c
                );
                property.Broker__r = null;
            }
            propertiesToInsert.add(property);
        }
        randomizeDateListed(propertiesToInsert);
        insert propertiesToInsert;
    }

    private static void insertMissingContacts() {
        List<Contact> sampleContacts = (List<Contact>) loadSampleData(
            'sample_data_contacts',
            List<Contact>.class
        );

        Set<String> emails = new Set<String>();
        for (Contact contact : sampleContacts) {
            emails.add(contact.Email);
        }
        Set<String> existingEmails = new Set<String>();
        for (Contact existing : [
            SELECT Email
            FROM Contact
            WHERE Email IN :emails
        ]) {
            existingEmails.add(normalize(existing.Email));
        }

        List<Contact> contactsToInsert = new List<Contact>();
        for (Contact contact : sampleContacts) {
            if (!existingEmails.contains(normalize(contact.Email))) {
                contactsToInsert.add(contact);
            }
        }
        insert contactsToInsert;
    }

    private static Object loadSampleData(
        String resourceName,
        System.Type listType
    ) {
        StaticResource resource = [
            SELECT Id, Body
            FROM StaticResource
            WHERE Name = :resourceName
        ];
        return JSON.deserialize(resource.Body.toString(), listType);
    }

    private static String propertyKey(Property__c property) {
        return normalize(property.Name) + '|' + normalize(property.Address__c);
    }

    private static String normalize(String value) {
        return value == null ? null : value.trim().toLowerCase();
    }

    private static void randomizeDateListed(List<Property__c> properties) {
        for (Property__c property : properties) {
            property.Date_Listed__c =
                System.today() - Integer.valueof((Math.random() * 90));
        }
    }
}
