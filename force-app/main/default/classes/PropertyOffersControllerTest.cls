@IsTest
private class PropertyOffersControllerTest {
    @TestSetup
    static void setup() {
        Id profileId = [
            SELECT Id
            FROM Profile
            WHERE Name = 'Standard User'
            LIMIT 1
        ]
        .Id;
        List<User> users = new List<User>();
        for (String role : new List<String>{ 'agent', 'broker' }) {
            users.add(
                new User(
                    Alias = role,
                    Email = role + '@offer-controller.test',
                    EmailEncodingKey = 'UTF-8',
                    LastName = role,
                    LanguageLocaleKey = 'en_US',
                    LocaleSidKey = 'en_US',
                    ProfileId = profileId,
                    TimeZoneSidKey = 'America/Los_Angeles',
                    Username = role +
                        '.' +
                        UserInfo.getOrganizationId() +
                        '@offer-controller.test'
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
    }
    private static User person(String role) {
        String email = role + '@offer-controller.test';
        return [SELECT Id FROM User WHERE Email = :email LIMIT 1];
    }
    @IsTest
    static void listSubmitRejectAndAccept() {
        System.runAs(person('agent')) {
            Property__c home = new Property__c(
                Name = 'Controller test',
                Price__c = 100000,
                Status__c = 'Available'
            );
            insert home;
            PropertyOffersController.OffersView empty = PropertyOffersController.getOffers(
                home.Id
            );
            Assert.areEqual(0, empty.offers.size());
            Assert.areEqual(100000, empty.askingPrice);
            Assert.areEqual('Available', empty.propertyStatus);
            Assert.isFalse(empty.canApprove);
            Id first = PropertyOffersController.submitOffer(
                home.Id,
                'First',
                95000
            );
            Id second = PropertyOffersController.submitOffer(
                home.Id,
                'Second',
                96000
            );
            PropertyOffersController.rejectOffer(second);
            PropertyOffersController.acceptOffer(first);
            PropertyOffersController.OffersView result = PropertyOffersController.getOffers(
                home.Id
            );
            Assert.areEqual(2, result.offers.size());
            Assert.areEqual('Under Agreement', result.propertyStatus);
        }
    }
    @IsTest
    static void approvalSuccess() {
        System.runAs(person('broker')) {
            Property__c home = new Property__c(
                Name = 'Approval',
                Price__c = 100000,
                Status__c = 'Available'
            );
            insert home;
            Id offerId = PropertyOffersController.submitOffer(
                home.Id,
                'Buyer',
                80000
            );
            Assert.isTrue(
                PropertyOffersController.getOffers(home.Id).canApprove
            );
            PropertyOffersController.approveOffer(offerId);
            Assert.areEqual(
                'Approved',
                [SELECT Status__c FROM Offer__c WHERE Id = :offerId].Status__c
            );
        }
    }
    @IsTest
    static void wrappedErrors() {
        System.runAs(person('agent')) {
            for (
                String operation : new List<String>{
                    'get',
                    'submit',
                    'approve',
                    'accept',
                    'reject'
                }
            ) {
                try {
                    if (operation == 'get') {
                        PropertyOffersController.getOffers(null);
                    } else if (operation == 'submit') {
                        PropertyOffersController.submitOffer(null, '', 0);
                    } else if (operation == 'approve') {
                        PropertyOffersController.approveOffer(null);
                    } else if (operation == 'accept') {
                        PropertyOffersController.acceptOffer(null);
                    } else {
                        PropertyOffersController.rejectOffer(null);
                    }
                    Assert.fail('Expected handled error');
                } catch (AuraHandledException error) {
                    Assert.isNotNull(error.getMessage());
                    Assert.areNotEqual(
                        'Script-thrown exception',
                        error.getMessage()
                    );
                }
            }
        }
    }
}
