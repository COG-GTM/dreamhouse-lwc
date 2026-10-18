@isTest
private class TestOfferController {
    private static User createUser(Boolean canApprove) {
        Profile standardUserProfile = [
            SELECT Id
            FROM Profile
            WHERE Name = 'Standard User'
            LIMIT 1
        ];
        String suffix = canApprove ? 'broker' : 'agent';
        User user = new User(
            Alias = suffix.left(8),
            Email = suffix + '@dreamhouse-offers-test.com',
            EmailEncodingKey = 'UTF-8',
            LastName = 'Testing',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            ProfileId = standardUserProfile.Id,
            TimeZoneSidKey = 'America/Los_Angeles',
            UserName = suffix +
                '@dreamhouse-offers-test-' +
                UserInfo.getOrganizationId() +
                '.com'
        );
        insert user;

        List<PermissionSetAssignment> assignments = new List<PermissionSetAssignment>{
            new PermissionSetAssignment(
                AssigneeId = user.Id,
                PermissionSetId = [
                    SELECT Id
                    FROM PermissionSet
                    WHERE Name = 'dreamhouse'
                ]
                .Id
            )
        };
        if (canApprove) {
            assignments.add(
                new PermissionSetAssignment(
                    AssigneeId = user.Id,
                    PermissionSetId = [
                        SELECT Id
                        FROM PermissionSet
                        WHERE Name = 'Dreamhouse_Broker'
                    ]
                    .Id
                )
            );
        }
        insert assignments;
        return user;
    }

    private static Id createProperty() {
        Property__c property = new Property__c(
            Name = 'Test Property',
            Price__c = 500000,
            Status__c = 'Available'
        );
        insert property;
        return property.Id;
    }

    @isTest
    static void testSubmitAndListOffers() {
        User agent = createUser(false);
        Id propertyId;
        System.runAs(new User(Id = UserInfo.getUserId())) {
            propertyId = createProperty();
        }

        System.runAs(agent) {
            Test.startTest();
            OfferController.submitOffer(propertyId, '  Jane Buyer ', 480000);
            OfferController.submitOffer(propertyId, 'Sam Lowball', 400000);
            List<Offer__c> offers = OfferController.getOffers(propertyId);
            Test.stopTest();

            Assert.areEqual(2, offers.size());
            Map<String, Offer__c> byBuyer = new Map<String, Offer__c>();
            for (Offer__c offer : offers) {
                byBuyer.put(offer.Buyer_Name__c, offer);
            }
            Assert.areEqual('Submitted', byBuyer.get('Jane Buyer').Status__c);
            Assert.areEqual(
                'Needs Approval',
                byBuyer.get('Sam Lowball').Status__c
            );
            Assert.isFalse(OfferController.canApproveOffers());
        }
    }

    @isTest
    static void testSubmitInvalidOfferThrows() {
        Id propertyId = createProperty();

        Test.startTest();
        try {
            OfferController.submitOffer(propertyId, 'Jane Buyer', -1);
            Assert.fail('Expected AuraHandledException');
        } catch (AuraHandledException e) {
            Assert.isTrue(e.getMessage().contains('greater than zero'));
        }
        Test.stopTest();
    }

    @isTest
    static void testAgentCannotApprove() {
        User agent = createUser(false);
        Id propertyId;
        System.runAs(new User(Id = UserInfo.getUserId())) {
            propertyId = createProperty();
        }

        System.runAs(agent) {
            Offer__c offer = OfferController.submitOffer(
                propertyId,
                'Sam Lowball',
                400000
            );
            Test.startTest();
            try {
                OfferController.approveOffer(offer.Id);
                Assert.fail('Expected AuraHandledException');
            } catch (AuraHandledException e) {
                Assert.isTrue(e.getMessage().contains('Approve Offers'));
            }
            try {
                OfferController.acceptOffer(offer.Id);
                Assert.fail('Expected AuraHandledException');
            } catch (AuraHandledException e) {
                Assert.isTrue(e.getMessage().contains('needs broker approval'));
            }
            Test.stopTest();
        }
    }

    @isTest
    static void testBrokerApprovesThenAccepts() {
        User broker = createUser(true);
        Id propertyId;
        System.runAs(new User(Id = UserInfo.getUserId())) {
            propertyId = createProperty();
        }

        System.runAs(broker) {
            Offer__c offer = OfferController.submitOffer(
                propertyId,
                'Sam Lowball',
                400000
            );
            Test.startTest();
            Assert.isTrue(OfferController.canApproveOffers());
            Assert.areEqual(
                'Approved',
                OfferController.approveOffer(offer.Id).Status__c
            );
            Assert.areEqual(
                'Accepted',
                OfferController.acceptOffer(offer.Id).Status__c
            );
            Test.stopTest();
        }

        Assert.areEqual(
            'Under Agreement',
            [SELECT Status__c FROM Property__c WHERE Id = :propertyId].Status__c
        );
    }

    @isTest
    static void testRejectOffer() {
        Id propertyId = createProperty();
        Offer__c offer = OfferController.submitOffer(
            propertyId,
            'Jane Buyer',
            480000
        );

        Test.startTest();
        Assert.areEqual(
            'Rejected',
            OfferController.rejectOffer(offer.Id).Status__c
        );
        Test.stopTest();
    }
}
