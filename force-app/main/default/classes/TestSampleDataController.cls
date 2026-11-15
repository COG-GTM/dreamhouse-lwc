@isTest
private class TestSampleDataController {
    private static List<SObject> loadSample(
        String resourceName,
        System.Type listType
    ) {
        StaticResource resource = [
            SELECT Body
            FROM StaticResource
            WHERE Name = :resourceName
        ];
        return (List<SObject>) JSON.deserialize(
            resource.Body.toString(),
            listType
        );
    }

    private static List<Broker__c> sampleBrokers() {
        return (List<Broker__c>) loadSample(
            'sample_data_brokers',
            List<Broker__c>.class
        );
    }

    private static List<Property__c> sampleProperties() {
        return (List<Property__c>) loadSample(
            'sample_data_properties',
            List<Property__c>.class
        );
    }

    private static List<Contact> sampleContacts() {
        return (List<Contact>) loadSample(
            'sample_data_contacts',
            List<Contact>.class
        );
    }

    @isTest
    static void importSampleData_emptyOrg_createsAllSampleRecords() {
        Test.startTest();
        SampleDataController.importSampleData();
        Test.stopTest();

        Assert.areEqual(
            sampleBrokers().size(),
            [SELECT COUNT() FROM Broker__c],
            'Every sample broker should be created.'
        );
        Assert.areEqual(
            sampleProperties().size(),
            [SELECT COUNT() FROM Property__c],
            'Every sample property should be created.'
        );
        Assert.areEqual(
            sampleContacts().size(),
            [SELECT COUNT() FROM Contact],
            'Every sample contact should be created.'
        );
        Assert.areEqual(
            0,
            [SELECT COUNT() FROM Property__c WHERE Broker__c = NULL],
            'Every sample property should be linked to its sample broker.'
        );
        for (Property__c property : [
            SELECT Date_Listed__c
            FROM Property__c
        ]) {
            Assert.isNotNull(
                property.Date_Listed__c,
                'Imported properties should get a listing date.'
            );
        }
    }

    @isTest
    static void importSampleData_existingRecords_areNotModifiedOrDeleted() {
        Broker__c unrelatedBroker = new Broker__c(
            Name = 'Existing Broker',
            Email__c = 'existing.broker@example.com',
            Phone__c = '555-0100'
        );
        Broker__c sampleBroker = sampleBrokers()[0];
        Broker__c existingSampleBroker = new Broker__c(
            Name = 'Renamed ' + sampleBroker.Name,
            Email__c = sampleBroker.Email__c,
            Phone__c = '555-0101'
        );
        insert new List<Broker__c>{ unrelatedBroker, existingSampleBroker };

        Property__c unrelatedProperty = new Property__c(
            Name = 'Existing Property',
            Address__c = '1 Shared Org Way',
            Price__c = 123456,
            Status__c = 'Available',
            Date_Listed__c = Date.newInstance(2020, 1, 1),
            Broker__c = unrelatedBroker.Id
        );
        Property__c sampleProperty = sampleProperties()[0];
        Property__c existingSampleProperty = new Property__c(
            Name = sampleProperty.Name,
            Address__c = sampleProperty.Address__c,
            Price__c = 1,
            Status__c = 'Closed',
            Date_Listed__c = Date.newInstance(2019, 6, 1),
            Broker__c = unrelatedBroker.Id
        );
        insert new List<Property__c>{
            unrelatedProperty,
            existingSampleProperty
        };

        Contact unrelatedContact = new Contact(
            LastName = 'Existing',
            Email = 'existing.contact@example.com',
            Phone = '555-0102'
        );
        Contact existingSampleContact = new Contact(
            LastName = 'Existing Sample',
            Email = sampleContacts()[0].Email,
            Phone = '555-0103'
        );
        insert new List<Contact>{ unrelatedContact, existingSampleContact };

        Case existingCase = new Case(Subject = 'Existing case');
        insert existingCase;

        Test.startTest();
        SampleDataController.importSampleData();
        Test.stopTest();

        Map<Id, Broker__c> brokers = new Map<Id, Broker__c>(
            [
                SELECT Name, Email__c, Phone__c
                FROM Broker__c
                WHERE
                    Id IN :new List<Id>{
                        unrelatedBroker.Id,
                        existingSampleBroker.Id
                    }
            ]
        );
        Assert.areEqual(2, brokers.size(), 'Existing brokers must survive.');
        Assert.areEqual(
            'Existing Broker',
            brokers.get(unrelatedBroker.Id).Name,
            'Existing broker must not be modified.'
        );
        Assert.areEqual(
            '555-0100',
            brokers.get(unrelatedBroker.Id).Phone__c,
            'Existing broker must not be modified.'
        );
        Assert.areEqual(
            'Renamed ' + sampleBroker.Name,
            brokers.get(existingSampleBroker.Id).Name,
            'A broker matching a sample email must not be overwritten.'
        );
        Assert.areEqual(
            '555-0101',
            brokers.get(existingSampleBroker.Id).Phone__c,
            'A broker matching a sample email must not be overwritten.'
        );
        Assert.areEqual(
            1,
            [
                SELECT COUNT()
                FROM Broker__c
                WHERE Email__c = :sampleBroker.Email__c
            ],
            'An existing sample broker must not be duplicated.'
        );

        Map<Id, Property__c> properties = new Map<Id, Property__c>(
            [
                SELECT
                    Name,
                    Address__c,
                    Price__c,
                    Status__c,
                    Date_Listed__c,
                    Broker__c
                FROM Property__c
                WHERE
                    Id IN :new List<Id>{
                        unrelatedProperty.Id,
                        existingSampleProperty.Id
                    }
            ]
        );
        Assert.areEqual(
            2,
            properties.size(),
            'Existing properties must survive.'
        );
        for (
            Property__c before : new List<Property__c>{
                unrelatedProperty,
                existingSampleProperty
            }
        ) {
            Property__c after = properties.get(before.Id);
            Assert.areEqual(before.Name, after.Name, 'Name changed.');
            Assert.areEqual(
                before.Address__c,
                after.Address__c,
                'Address changed.'
            );
            Assert.areEqual(before.Price__c, after.Price__c, 'Price changed.');
            Assert.areEqual(
                before.Status__c,
                after.Status__c,
                'Status changed.'
            );
            Assert.areEqual(
                before.Date_Listed__c,
                after.Date_Listed__c,
                'Date listed changed.'
            );
            Assert.areEqual(
                before.Broker__c,
                after.Broker__c,
                'Broker changed.'
            );
        }
        Assert.areEqual(
            1,
            [
                SELECT COUNT()
                FROM Property__c
                WHERE
                    Name = :sampleProperty.Name
                    AND Address__c = :sampleProperty.Address__c
            ],
            'An existing sample property must not be duplicated.'
        );
        Assert.areEqual(
            sampleProperties().size() + 1,
            [SELECT COUNT() FROM Property__c],
            'Only the missing sample properties should be added.'
        );

        Set<Id> sampleBrokerPropertyBrokers = new Set<Id>();
        for (Property__c imported : [
            SELECT Broker__c
            FROM Property__c
            WHERE
                Broker__r.Email__c = :sampleBroker.Email__c
                AND Id != :existingSampleProperty.Id
        ]) {
            sampleBrokerPropertyBrokers.add(imported.Broker__c);
        }
        Assert.areEqual(
            new Set<Id>{ existingSampleBroker.Id },
            sampleBrokerPropertyBrokers,
            'New sample properties should link to the existing sample broker.'
        );

        Map<Id, Contact> contacts = new Map<Id, Contact>(
            [
                SELECT LastName, Phone
                FROM Contact
                WHERE
                    Id IN :new List<Id>{
                        unrelatedContact.Id,
                        existingSampleContact.Id
                    }
            ]
        );
        Assert.areEqual(2, contacts.size(), 'Existing contacts must survive.');
        Assert.areEqual(
            '555-0102',
            contacts.get(unrelatedContact.Id).Phone,
            'Existing contact must not be modified.'
        );
        Assert.areEqual(
            'Existing Sample',
            contacts.get(existingSampleContact.Id).LastName,
            'A contact matching a sample email must not be overwritten.'
        );
        Assert.areEqual(
            sampleContacts().size() + 1,
            [SELECT COUNT() FROM Contact],
            'Only the missing sample contacts should be added.'
        );

        Assert.areEqual(
            1,
            [SELECT COUNT() FROM Case WHERE Id = :existingCase.Id],
            'Existing cases must survive.'
        );
    }

    @isTest
    static void importSampleData_runTwice_keepsFirstImportAndAddsNothing() {
        SampleDataController.importSampleData();
        Map<Id, Property__c> firstImport = new Map<Id, Property__c>(
            [SELECT Id, Date_Listed__c FROM Property__c]
        );
        Integer brokerCount = [SELECT COUNT() FROM Broker__c];
        Integer contactCount = [SELECT COUNT() FROM Contact];

        Test.startTest();
        SampleDataController.importSampleData();
        Test.stopTest();

        Map<Id, Property__c> afterSecondImport = new Map<Id, Property__c>(
            [SELECT Id, Date_Listed__c FROM Property__c]
        );
        Assert.areEqual(
            firstImport.keySet(),
            afterSecondImport.keySet(),
            'A second import must not delete or add properties.'
        );
        for (Id propertyId : firstImport.keySet()) {
            Assert.areEqual(
                firstImport.get(propertyId).Date_Listed__c,
                afterSecondImport.get(propertyId).Date_Listed__c,
                'A second import must not modify existing properties.'
            );
        }
        Assert.areEqual(
            brokerCount,
            [SELECT COUNT() FROM Broker__c],
            'A second import must not add brokers.'
        );
        Assert.areEqual(
            contactCount,
            [SELECT COUNT() FROM Contact],
            'A second import must not add contacts.'
        );
    }
}
