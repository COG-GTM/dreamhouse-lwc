@isTest
private class TestPropertyController {
    private final static String MOCK_PICTURE_NAME = 'MockPictureName';

    public static void createProperties(Integer amount) {
        List<Property__c> properties = new List<Property__c>();
        for (Integer i = 0; i < amount; i++) {
            properties.add(
                new Property__c(
                    Name = 'Name ' + i,
                    Price__c = 20000,
                    Beds__c = 3,
                    Baths__c = 3
                )
            );
        }
        insert properties;
    }

    @isTest
    static void testGetPagedPropertyList() {
        Profile standardUserProfile = [
            SELECT Name, Id
            FROM Profile
            WHERE
                UserType = 'Standard'
                AND PermissionsPrivacyDataAccess = FALSE
                AND PermissionsSubmitMacrosAllowed = TRUE
                AND PermissionsMassInlineEdit = TRUE
            LIMIT 1
        ];
        User testUser = new User(
            Alias = 'standt',
            Email = 'standarduser@testorg.com',
            EmailEncodingKey = 'UTF-8',
            LastName = 'Testing',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            ProfileId = standardUserProfile.Id,
            TimeZoneSidKey = 'America/Los_Angeles',
            UserName = 'standarduser@dreamhouse-testorg.com'
        );
        insert testUser;
        PermissionSet ps = [
            SELECT Id
            FROM PermissionSet
            WHERE Name = 'dreamhouse'
        ];
        insert new PermissionSetAssignment(
            AssigneeId = testUser.Id,
            PermissionSetId = ps.Id
        );

        // Insert test properties as admin
        System.runAs(new User(Id = UserInfo.getUserId())) {
            TestPropertyController.createProperties(5);
        }
        // Read properties as test user
        System.runAs(testUser) {
            Test.startTest();
            PagedResult result = PropertyController.getPagedPropertyList(
                '',
                999999,
                0,
                0,
                10,
                1
            );
            Test.stopTest();
            Assert.areEqual(5, result.records.size());
        }
    }

    @isTest
    static void testGetPicturesNoResults() {
        Property__c property = new Property__c(Name = 'Name');
        insert property;

        Test.startTest();
        List<ContentVersion> items = PropertyController.getPictures(
            property.Id
        );
        Test.stopTest();

        Assert.isNull(items);
    }

    @isTest
    static void testGetPicturesWithResults() {
        Property__c property = new Property__c(Name = 'Name');
        insert property;

        // Insert mock picture
        ContentVersion picture = new Contentversion();
        picture.Title = MOCK_PICTURE_NAME;
        picture.PathOnClient = 'picture.png';
        picture.Versiondata = EncodingUtil.base64Decode('MockValue');
        insert picture;

        // Link picture to property record
        List<ContentDocument> documents = [
            SELECT Id, Title, LatestPublishedVersionId
            FROM ContentDocument
            LIMIT 1
        ];
        ContentDocumentLink link = new ContentDocumentLink();
        link.LinkedEntityId = property.Id;
        link.ContentDocumentId = documents[0].Id;
        link.shareType = 'V';
        insert link;

        Test.startTest();
        List<ContentVersion> items = PropertyController.getPictures(
            property.Id
        );
        Test.stopTest();

        Assert.areEqual(1, items.size());
        Assert.areEqual(MOCK_PICTURE_NAME, items[0].Title);
    }

    private static Property__c buildProperty(
        String name,
        String city,
        String tags,
        Decimal price,
        Integer beds,
        Integer baths
    ) {
        return new Property__c(
            Name = name,
            City__c = city,
            Tags__c = tags,
            Price__c = price,
            Beds__c = beds,
            Baths__c = baths
        );
    }

    private static Id linkFile(Id recordId, String title, String fileName) {
        ContentVersion version = new ContentVersion(
            Title = title,
            PathOnClient = fileName,
            VersionData = Blob.valueOf('MockValue')
        );
        insert version;
        Id documentId = [
            SELECT ContentDocumentId
            FROM ContentVersion
            WHERE Id = :version.Id
        ]
        .ContentDocumentId;
        insert new ContentDocumentLink(
            LinkedEntityId = recordId,
            ContentDocumentId = documentId,
            ShareType = 'V'
        );
        return documentId;
    }

    @isTest
    static void getPagedPropertyListMatchesSearchKeyOnNameCityAndTags() {
        insert new List<Property__c>{
            buildProperty('Harbor Loft', 'Boston', 'modern', 100000, 2, 1),
            buildProperty('Elm Cottage', 'Harborview', 'cozy', 200000, 2, 1),
            buildProperty('Pine House', 'Cambridge', 'harbor', 300000, 2, 1),
            buildProperty('Oak Villa', 'Newton', 'garden', 400000, 2, 1)
        };

        Test.startTest();
        PagedResult result = PropertyController.getPagedPropertyList(
            'Harbor',
            null,
            null,
            null,
            null,
            null
        );
        Test.stopTest();

        Assert.areEqual(
            3,
            result.totalItemCount,
            'Name, City and Tags matches should be counted'
        );
        Assert.areEqual(3, result.records.size(), 'Expected 3 matches');
        for (Object record : result.records) {
            Assert.areNotEqual(
                'Oak Villa',
                ((Property__c) record).Name,
                'Non-matching property should be excluded'
            );
        }
    }

    @isTest
    static void getPagedPropertyListFiltersByMaxPrice() {
        insert new List<Property__c>{
            buildProperty('Below', 'Boston', null, 499999, 2, 1),
            buildProperty('Equal', 'Boston', null, 500000, 2, 1),
            buildProperty('Above', 'Boston', null, 500001, 2, 1)
        };

        Test.startTest();
        PagedResult result = PropertyController.getPagedPropertyList(
            '',
            500000,
            0,
            0,
            10,
            1
        );
        Test.stopTest();

        Assert.areEqual(2, result.totalItemCount, 'Max price is inclusive');
        Assert.areEqual(
            'Below',
            ((Property__c) result.records[0]).Name,
            'Cheapest property first'
        );
        Assert.areEqual(
            'Equal',
            ((Property__c) result.records[1]).Name,
            'Property priced at the max should be included'
        );
    }

    @isTest
    static void getPagedPropertyListFiltersByMinBedroomsAndBathrooms() {
        insert new List<Property__c>{
            buildProperty('Too Few Beds', 'Boston', null, 100000, 2, 3),
            buildProperty('Too Few Baths', 'Boston', null, 200000, 4, 1),
            buildProperty('Exact Match', 'Boston', null, 300000, 3, 2),
            buildProperty('Larger', 'Boston', null, 400000, 5, 4)
        };

        Test.startTest();
        PagedResult result = PropertyController.getPagedPropertyList(
            '',
            null,
            3,
            2,
            10,
            1
        );
        Test.stopTest();

        Assert.areEqual(
            2,
            result.totalItemCount,
            'Only properties meeting both minimums should match'
        );
        Assert.areEqual(
            'Exact Match',
            ((Property__c) result.records[0]).Name,
            'Minimums are inclusive'
        );
        Assert.areEqual('Larger', ((Property__c) result.records[1]).Name);
    }

    @isTest
    static void getPagedPropertyListAppliesDefaultsForNullInputs() {
        createProperties(12);

        Test.startTest();
        PagedResult result = PropertyController.getPagedPropertyList(
            '',
            null,
            null,
            null,
            null,
            null
        );
        Test.stopTest();

        Assert.areEqual(9, result.pageSize, 'Default page size is 9');
        Assert.areEqual(1, result.pageNumber, 'Default page number is 1');
        Assert.areEqual(
            12,
            result.totalItemCount,
            'Total should count every match, not just the page'
        );
        Assert.areEqual(
            9,
            result.records.size(),
            'Records should be limited to the default page size'
        );
    }

    @isTest
    static void getPagedPropertyListAppliesDefaultFiltersForNullInputs() {
        insert new List<Property__c>{
            buildProperty('At Default Max', 'Boston', null, 9999999, 0, 0),
            buildProperty('Above Default Max', 'Boston', null, 10000000, 0, 0)
        };

        Test.startTest();
        PagedResult result = PropertyController.getPagedPropertyList(
            '',
            null,
            null,
            null,
            null,
            null
        );
        Test.stopTest();

        Assert.areEqual(
            1,
            result.totalItemCount,
            'Default max price is 9999999 and default minimum rooms are 0'
        );
        Assert.areEqual(
            'At Default Max',
            ((Property__c) result.records[0]).Name,
            'Property at the default boundaries should be included'
        );
    }

    @isTest
    static void getPagedPropertyListReturnsRequestedPageSortedByPrice() {
        List<Property__c> properties = new List<Property__c>();
        for (Integer i = 10; i >= 1; i--) {
            properties.add(
                buildProperty('Property ' + i, 'Boston', null, i * 1000, 3, 2)
            );
        }
        insert properties;

        Test.startTest();
        PagedResult result = PropertyController.getPagedPropertyList(
            '',
            null,
            null,
            null,
            4,
            2
        );
        Test.stopTest();

        Assert.areEqual(4, result.pageSize);
        Assert.areEqual(2, result.pageNumber);
        Assert.areEqual(10, result.totalItemCount);
        Assert.areEqual(4, result.records.size(), 'Second page should be full');
        for (Integer i = 0; i < result.records.size(); i++) {
            Assert.areEqual(
                (i + 5) * 1000,
                ((Property__c) result.records[i]).Price__c,
                'Page 2 should hold the 5th to 8th cheapest properties'
            );
        }
    }

    @isTest
    static void getPagedPropertyListReturnsPartialLastPage() {
        createProperties(10);

        Test.startTest();
        PagedResult result = PropertyController.getPagedPropertyList(
            '',
            null,
            null,
            null,
            4,
            3
        );
        Test.stopTest();

        Assert.areEqual(10, result.totalItemCount);
        Assert.areEqual(
            2,
            result.records.size(),
            'Last page should hold the remaining records'
        );
    }

    @isTest
    static void getPagedPropertyListReturnsEmptyResultWhenNothingMatches() {
        createProperties(3);

        Test.startTest();
        PagedResult result = PropertyController.getPagedPropertyList(
            'NoSuchProperty',
            null,
            null,
            null,
            null,
            null
        );
        Test.stopTest();

        Assert.areEqual(0, result.totalItemCount);
        Assert.isTrue(result.records.isEmpty(), 'Expected no records');
    }

    @isTest
    static void getPagedPropertyListThrowsForUserWithoutPropertyAccess() {
        Profile standardUserProfile = [
            SELECT Id
            FROM Profile
            WHERE Name = 'Standard User'
        ];
        User userWithoutAccess = new User(
            Alias = 'noaccess',
            Email = 'noaccess@testorg.com',
            EmailEncodingKey = 'UTF-8',
            LastName = 'NoAccess',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            ProfileId = standardUserProfile.Id,
            TimeZoneSidKey = 'America/Los_Angeles',
            UserName = 'noaccess@dreamhouse-testorg.com'
        );
        insert userWithoutAccess;
        System.runAs(new User(Id = UserInfo.getUserId())) {
            createProperties(3);
        }

        System.runAs(userWithoutAccess) {
            Test.startTest();
            try {
                PropertyController.getPagedPropertyList(
                    '',
                    null,
                    null,
                    null,
                    null,
                    null
                );
                Assert.fail(
                    'Expected a QueryException for a user without Property__c access'
                );
            } catch (QueryException e) {
                Assert.isNotNull(
                    e.getMessage(),
                    'WITH USER_MODE should reject the records query'
                );
            }
            Test.stopTest();
        }
    }

    @isTest
    static void getPagedPropertyListThrowsForPageNumberZero() {
        createProperties(3);

        Test.startTest();
        try {
            PropertyController.getPagedPropertyList('', null, null, null, 9, 0);
            Assert.fail('Expected a QueryException for a negative OFFSET');
        } catch (QueryException e) {
            Assert.isNotNull(e.getMessage(), 'Page 0 gives OFFSET -9');
        }
        Test.stopTest();
    }

    @isTest
    static void getPagedPropertyListThrowsForNegativePageNumber() {
        createProperties(3);

        Test.startTest();
        try {
            PropertyController.getPagedPropertyList(
                '',
                null,
                null,
                null,
                9,
                -1
            );
            Assert.fail('Expected a QueryException for a negative OFFSET');
        } catch (QueryException e) {
            Assert.isNotNull(e.getMessage(), 'Page -1 gives OFFSET -18');
        }
        Test.stopTest();
    }

    @isTest
    static void getPicturesIgnoresNonImageFiles() {
        Property__c property = new Property__c(Name = 'Name');
        insert property;
        linkFile(property.Id, 'Contract', 'contract.pdf');
        linkFile(property.Id, 'Notes', 'notes.txt');

        Test.startTest();
        List<ContentVersion> items = PropertyController.getPictures(
            property.Id
        );
        Test.stopTest();

        Assert.isNull(items, 'Non-image files should not be returned');
    }

    @isTest
    static void getPicturesReturnsOnlyImagesForTheProperty() {
        Property__c property = new Property__c(Name = 'Name');
        Property__c otherProperty = new Property__c(Name = 'Other');
        insert new List<Property__c>{ property, otherProperty };
        linkFile(property.Id, 'Front', 'front.png');
        linkFile(property.Id, 'Kitchen', 'kitchen.jpg');
        linkFile(property.Id, 'Tour', 'tour.gif');
        linkFile(property.Id, 'Contract', 'contract.pdf');
        linkFile(otherProperty.Id, 'Elsewhere', 'elsewhere.png');

        Test.startTest();
        List<ContentVersion> items = PropertyController.getPictures(
            property.Id
        );
        Test.stopTest();

        Set<String> titles = new Set<String>();
        for (ContentVersion item : items) {
            titles.add(item.Title);
        }
        Assert.areEqual(
            new Set<String>{ 'Front', 'Kitchen', 'Tour' },
            titles,
            'Only PNG, JPG and GIF files linked to the property should be returned'
        );
    }

    @isTest
    static void getPicturesReturnsLatestVersionOnly() {
        Property__c property = new Property__c(Name = 'Name');
        insert property;
        Id documentId = linkFile(property.Id, 'Original', 'picture.png');
        insert new ContentVersion(
            ContentDocumentId = documentId,
            Title = 'Updated',
            PathOnClient = 'picture.png',
            VersionData = Blob.valueOf('NewValue')
        );

        Test.startTest();
        List<ContentVersion> items = PropertyController.getPictures(
            property.Id
        );
        Test.stopTest();

        Assert.areEqual(1, items.size(), 'Only one version per picture');
        Assert.areEqual('Updated', items[0].Title);
    }
}
