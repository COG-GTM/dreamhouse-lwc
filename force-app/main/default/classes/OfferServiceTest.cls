@IsTest
private class OfferServiceTest {
    @TestSetup
    static void setup() {
        Profile profile = [
            SELECT Id
            FROM Profile
            WHERE Name = 'Standard User'
            LIMIT 1
        ];
        List<User> users = new List<User>();
        for (String role : new List<String>{ 'agent', 'broker' }) {
            users.add(
                new User(
                    Alias = role,
                    Email = role + '@offers.test',
                    EmailEncodingKey = 'UTF-8',
                    LastName = role,
                    LanguageLocaleKey = 'en_US',
                    LocaleSidKey = 'en_US',
                    ProfileId = profile.Id,
                    TimeZoneSidKey = 'America/Los_Angeles',
                    Username = role +
                        '.' +
                        UserInfo.getOrganizationId() +
                        '@offers.test'
                )
            );
        }
        insert users;
        Map<String, Id> permissions = new Map<String, Id>();
        for (PermissionSet permission : [
            SELECT Id, Name
            FROM PermissionSet
            WHERE Name IN ('dreamhouse', 'Dreamhouse_Broker')
        ]) {
            permissions.put(permission.Name, permission.Id);
        }
        List<PermissionSetAssignment> assignments = new List<PermissionSetAssignment>();
        for (User person : users) {
            assignments.add(
                new PermissionSetAssignment(
                    AssigneeId = person.Id,
                    PermissionSetId = permissions.get('dreamhouse')
                )
            );
            if (person.Alias == 'broker') {
                assignments.add(
                    new PermissionSetAssignment(
                        AssigneeId = person.Id,
                        PermissionSetId = permissions.get('Dreamhouse_Broker')
                    )
                );
            }
        }
        insert assignments;
        System.runAs(users[0]) {
            insert new Property__c(
                Name = 'Offer test',
                Price__c = 100000,
                Status__c = 'Available'
            );
        }
    }
    private static User person(String alias) {
        return [
            SELECT Id
            FROM User
            WHERE Alias = :alias AND Email = :alias + '@offers.test'
            LIMIT 1
        ];
    }
    private static Property__c property() {
        return [
            SELECT Id, Status__c, Price__c
            FROM Property__c
            WHERE Name = 'Offer test'
            LIMIT 1
        ];
    }
    @IsTest
    static void submitAndRounding() {
        System.runAs(person('agent')) {
            Property__c home = property();
            Id exact = OfferService.submit(home.Id, ' Exact ', 90000);
            Id roundedDown = OfferService.submit(home.Id, 'Down', 89960);
            Id roundedUp = OfferService.submit(home.Id, 'Up', 89950);
            Id above = OfferService.submit(home.Id, 'Above', 110050);
            Map<Id, Offer__c> offers = new Map<Id, Offer__c>(
                [
                    SELECT Buyer_Name__c, Status__c, Percent_Below_Asking__c
                    FROM Offer__c
                ]
            );
            Assert.areEqual('Exact', offers.get(exact).Buyer_Name__c);
            Assert.areEqual('Submitted', offers.get(exact).Status__c);
            Assert.areEqual(
                10.0,
                offers.get(roundedDown).Percent_Below_Asking__c
            );
            Assert.areEqual('Submitted', offers.get(roundedDown).Status__c);
            Assert.areEqual(
                10.1,
                offers.get(roundedUp).Percent_Below_Asking__c
            );
            Assert.areEqual('Needs Approval', offers.get(roundedUp).Status__c);
            Assert.areEqual(-10.1, offers.get(above).Percent_Below_Asking__c);
            Assert.isFalse(OfferService.isChangingStatus());
        }
    }
    @IsTest
    static void approvalPermissionsAndAccept() {
        Id homeId = property().Id;
        Id discounted;
        Id other;
        Id submitted;
        Id rejected;
        System.runAs(person('agent')) {
            discounted = OfferService.submit(homeId, 'Discounted', 80000);
            other = OfferService.submit(homeId, 'Other', 85000);
            submitted = OfferService.submit(homeId, 'Submitted', 95000);
            rejected = OfferService.submit(homeId, 'Rejected', 98000);
            OfferService.reject(rejected);
            Assert.isFalse(OfferService.canApprove());
            expectActionFailure('approve', discounted, 'permission');
            expectActionFailure('accept', discounted, 'approval');
        }
        System.runAs(person('broker')) {
            Assert.isTrue(OfferService.canApprove());
            OfferService.approve(discounted);
            OfferService.approve(other);
            expectActionFailure('approve', discounted, 'Only offers');
            Test.startTest();
            OfferService.accept(discounted);
            Test.stopTest();
            Map<Id, Offer__c> offers = new Map<Id, Offer__c>(
                [SELECT Status__c FROM Offer__c]
            );
            Assert.areEqual('Accepted', offers.get(discounted).Status__c);
            for (Id offerId : new List<Id>{ other, submitted, rejected }) {
                Assert.areEqual('Rejected', offers.get(offerId).Status__c);
            }
            Property__c updated = [
                SELECT Status__c, Date_Agreement__c
                FROM Property__c
                WHERE Id = :homeId
            ];
            Assert.areEqual('Under Agreement', updated.Status__c);
            Assert.areEqual(Date.today(), updated.Date_Agreement__c);
            expectActionFailure('reject', discounted, 'final');
            expectActionFailure('accept', other, 'final');
            Assert.isFalse(OfferService.isChangingStatus());
        }
    }
    @IsTest
    static void acceptSubmittedAndUnavailable() {
        System.runAs(person('agent')) {
            Property__c home = property();
            Id offerId = OfferService.submit(home.Id, 'Buyer', 95000);
            for (
                String status : new List<String>{ 'Closed', 'Under Agreement' }
            ) {
                home.Status__c = status;
                update home;
                expectActionFailure('accept', offerId, 'no longer');
                expectSubmitFailure(home.Id, 'Buyer', 95000);
            }
            home.Status__c = 'Available';
            update home;
            OfferService.accept(offerId);
            Assert.areEqual(
                'Accepted',
                [SELECT Status__c FROM Offer__c WHERE Id = :offerId].Status__c
            );
        }
    }
    @IsTest
    static void invalidSubmissions() {
        System.runAs(person('agent')) {
            Property__c home = property();
            expectSubmitFailure(null, 'Buyer', 1);
            expectSubmitFailure(home.Id, ' ', 1);
            expectSubmitFailure(home.Id, 'Buyer', null);
            expectSubmitFailure(home.Id, 'Buyer', 0);
            expectSubmitFailure(home.Id, 'Buyer', -1);
            for (Decimal price : new List<Decimal>{ null, 0, -1 }) {
                home.Price__c = price;
                update home;
                expectSubmitFailure(home.Id, 'Buyer', 1);
            }
        }
    }
    @IsTest
    static void triggerGuardsAndBulkInsert() {
        System.runAs(person('agent')) {
            Id homeId = property().Id;
            List<Offer__c> offers = new List<Offer__c>();
            for (Integer i = 0; i < 20; i++) {
                offers.add(
                    new Offer__c(
                        Property__c = homeId,
                        Buyer_Name__c = 'Buyer ' + i,
                        Amount__c = 95000,
                        Status__c = 'Accepted'
                    )
                );
            }
            insert as user offers;
            Offer__c original = [
                SELECT Id, Status__c
                FROM Offer__c
                WHERE Id = :offers[0].Id
            ];
            Assert.areEqual('Submitted', original.Status__c);
            List<Offer__c> changes = new List<Offer__c>{
                new Offer__c(Id = offers[0].Id, Amount__c = 100),
                new Offer__c(Id = offers[1].Id, Percent_Below_Asking__c = 99),
                new Offer__c(Id = offers[2].Id, Status__c = 'Approved')
            };
            for (Database.SaveResult result : Database.update(changes, false)) {
                Assert.isFalse(result.isSuccess());
                Assert.isTrue(
                    result.getErrors()[0]
                        .getMessage()
                        .contains('cannot be changed') ||
                    result.getErrors()[0].getMessage().contains('offer actions')
                );
            }
            List<Offer__c> invalid = new List<Offer__c>{
                new Offer__c(
                    Property__c = homeId,
                    Buyer_Name__c = 'Buyer',
                    Amount__c = 0
                ),
                new Offer__c(
                    Property__c = homeId,
                    Buyer_Name__c = ' ',
                    Amount__c = 1
                ),
                new Offer__c(Property__c = homeId, Buyer_Name__c = 'Buyer'),
                new Offer__c(Buyer_Name__c = 'Buyer', Amount__c = 1)
            };
            for (Database.SaveResult result : Database.insert(invalid, false)) {
                Assert.isFalse(result.isSuccess());
            }
        }
    }
    private static void expectSubmitFailure(
        Id homeId,
        String buyer,
        Decimal amount
    ) {
        try {
            OfferService.submit(homeId, buyer, amount);
            Assert.fail('Expected invalid submission to fail');
        } catch (Exception error) {
            Assert.isFalse(error instanceof System.AssertException);
        }
    }
    private static void expectActionFailure(
        String action,
        Id offerId,
        String message
    ) {
        try {
            if (action == 'approve') {
                OfferService.approve(offerId);
            } else if (action == 'accept') {
                OfferService.accept(offerId);
            } else {
                OfferService.reject(offerId);
            }
            Assert.fail('Expected action to fail');
        } catch (OfferService.OfferException error) {
            Assert.isTrue(
                error.getMessage().contains(message),
                error.getMessage()
            );
        }
    }
}
