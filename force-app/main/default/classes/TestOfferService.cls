@isTest
public class TestOfferService {
    private static final Decimal ASKING = 845000;

    public static User createUser(Boolean broker) {
        Profile standardUserProfile = [
            SELECT Id
            FROM Profile
            WHERE
                UserType = 'Standard'
                AND PermissionsPrivacyDataAccess = FALSE
                AND PermissionsSubmitMacrosAllowed = TRUE
                AND PermissionsMassInlineEdit = TRUE
            LIMIT 1
        ];
        User user = new User(
            Alias = broker ? 'broker' : 'agent',
            Email = 'offers@testorg.com',
            EmailEncodingKey = 'UTF-8',
            LastName = broker ? 'Broker' : 'Agent',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            ProfileId = standardUserProfile.Id,
            TimeZoneSidKey = 'America/Los_Angeles',
            UserName = 'offers-' +
                (broker ? 'broker' : 'agent') +
                '@dreamhouse-testorg.com'
        );
        System.runAs(new User(Id = UserInfo.getUserId())) {
            insert user;
            List<String> permissionSets = broker
                ? new List<String>{ 'dreamhouse', 'Dreamhouse_Broker' }
                : new List<String>{ 'dreamhouse' };
            List<PermissionSetAssignment> assignments = new List<PermissionSetAssignment>();
            for (PermissionSet ps : [
                SELECT Id
                FROM PermissionSet
                WHERE Name IN :permissionSets
            ]) {
                assignments.add(
                    new PermissionSetAssignment(
                        AssigneeId = user.Id,
                        PermissionSetId = ps.Id
                    )
                );
            }
            insert assignments;
        }
        return user;
    }

    public static Property__c createProperty(String status) {
        Property__c property = new Property__c(
            Name = 'Offer Test Property',
            Price__c = ASKING,
            Status__c = status
        );
        insert property;
        return property;
    }

    private static Offer__c reload(Id offerId) {
        return [
            SELECT
                Status__c,
                Percent_Below_Asking__c,
                Approved_Percent_Below__c,
                Amount__c
            FROM Offer__c
            WHERE Id = :offerId
        ];
    }

    private static String errorOf(Exception e) {
        return e instanceof DmlException
            ? ((DmlException) e).getDmlMessage(0)
            : e.getMessage();
    }

    @isTest
    static void percentBelowAskingRoundsToOneDecimalHalfUp() {
        Assert.areEqual(14.8, OfferService.percentBelowAsking(845000, 720000));
        Assert.areEqual(3.0, OfferService.percentBelowAsking(845000, 820000));
        Assert.areEqual(10.1, OfferService.percentBelowAsking(1000, 899.5));
        Assert.areEqual(10.0, OfferService.percentBelowAsking(1000, 899.6));
        Assert.areEqual(-5.0, OfferService.percentBelowAsking(1000, 1050));
    }

    @isTest
    static void submitSetsStatusFromDiscount() {
        Property__c property = createProperty('Available');
        User agent = createUser(false);
        System.runAs(agent) {
            Test.startTest();
            Offer__c near = OfferService.submitOffer(
                property.Id,
                ' Jane Buyer ',
                820000
            );
            Offer__c low = OfferService.submitOffer(
                property.Id,
                'Sam Lowball',
                720000
            );
            Offer__c boundary = OfferService.submitOffer(
                property.Id,
                'Edge Case',
                760500
            );
            Test.stopTest();
            Assert.areEqual('Submitted', reload(near.Id).Status__c);
            Assert.areEqual(3.0, reload(near.Id).Percent_Below_Asking__c);
            Assert.areEqual('Needs Approval', reload(low.Id).Status__c);
            Assert.areEqual(14.8, reload(low.Id).Percent_Below_Asking__c);
            Assert.areEqual('Submitted', reload(boundary.Id).Status__c);
            Assert.areEqual(10.0, reload(boundary.Id).Percent_Below_Asking__c);
        }
        Assert.areEqual(
            'Jane Buyer',
            [SELECT Buyer_Name__c FROM Offer__c WHERE Amount__c = 820000]
            .Buyer_Name__c
        );
    }

    @isTest
    static void submitRejectsInvalidInput() {
        Property__c property = createProperty('Available');
        Map<String, Decimal> invalid = new Map<String, Decimal>{
            '' => 100,
            'Zero' => 0,
            'Negative' => -1,
            'Null' => null
        };
        for (String buyer : invalid.keySet()) {
            try {
                OfferService.submitOffer(
                    property.Id,
                    buyer,
                    invalid.get(buyer)
                );
                Assert.fail('Expected an error for ' + buyer);
            } catch (OfferService.OfferException e) {
                Assert.isNotNull(e.getMessage());
            }
        }
        Assert.areEqual(0, [SELECT COUNT() FROM Offer__c]);
    }

    @isTest
    static void submitBlockedOnClosedProperties() {
        for (
            String status : new List<String>{
                'Under Agreement',
                'Contracted',
                'Closed'
            }
        ) {
            Property__c property = createProperty(status);
            try {
                OfferService.submitOffer(property.Id, 'Jane', 800000);
                Assert.fail('Expected an error for ' + status);
            } catch (OfferService.OfferException e) {
                Assert.isTrue(e.getMessage().contains(status));
            }
        }
    }

    @isTest
    static void submitRequiresAskingPrice() {
        Property__c property = new Property__c(
            Name = 'No Price',
            Status__c = 'Available'
        );
        insert property;
        try {
            OfferService.submitOffer(property.Id, 'Jane', 800000);
            Assert.fail('Expected an error');
        } catch (OfferService.OfferException e) {
            Assert.isTrue(e.getMessage().contains('asking price'));
        }
        try {
            insert new Offer__c(
                Property__c = property.Id,
                Buyer_Name__c = 'Direct',
                Amount__c = 1000
            );
            Assert.fail('Expected trigger error');
        } catch (DmlException e) {
            Assert.isTrue(errorOf(e).contains('asking price'));
        }
    }

    @isTest
    static void agentCannotApproveButBrokerCan() {
        Property__c property = createProperty('Available');
        Offer__c offer = OfferService.submitOffer(
            property.Id,
            'Sam Lowball',
            720000
        );
        User agent = createUser(false);
        System.runAs(agent) {
            Assert.isFalse(OfferService.canApprove());
            try {
                OfferService.approveOffer(offer.Id);
                Assert.fail('Agent should not approve');
            } catch (OfferService.OfferException e) {
                Assert.isTrue(e.getMessage().contains('Approve Offers'));
            }
        }
        Assert.areEqual('Needs Approval', reload(offer.Id).Status__c);
    }

    @isTest
    static void brokerApprovesThenAcceptRejectsOthers() {
        Property__c property = createProperty('Available');
        User broker = createUser(true);
        System.runAs(broker) {
            Offer__c jane = OfferService.submitOffer(
                property.Id,
                'Jane Buyer',
                820000
            );
            Offer__c sam = OfferService.submitOffer(
                property.Id,
                'Sam Lowball',
                720000
            );
            try {
                OfferService.acceptOffer(sam.Id);
                Assert.fail('Needs approval first');
            } catch (OfferService.OfferException e) {
                Assert.isTrue(e.getMessage().contains('approval'));
            }
            try {
                OfferService.approveOffer(jane.Id);
                Assert.fail('Jane does not need approval');
            } catch (OfferService.OfferException e) {
                Assert.isTrue(e.getMessage().contains('need approval'));
            }
            Test.startTest();
            OfferService.approveOffer(sam.Id);
            Assert.areEqual('Approved', reload(sam.Id).Status__c);
            Assert.areEqual(14.8, reload(sam.Id).Approved_Percent_Below__c);
            OfferService.acceptOffer(sam.Id);
            Test.stopTest();
            Assert.areEqual('Accepted', reload(sam.Id).Status__c);
            Assert.areEqual('Rejected', reload(jane.Id).Status__c);
        }
        Property__c updated = [
            SELECT Status__c, Date_Agreement__c
            FROM Property__c
            WHERE Id = :property.Id
        ];
        Assert.areEqual('Under Agreement', updated.Status__c);
        Assert.areEqual(Date.today(), updated.Date_Agreement__c);
    }

    @isTest
    static void cannotActOnceUnderAgreement() {
        Property__c property = createProperty('Available');
        Offer__c first = OfferService.submitOffer(property.Id, 'A', 840000);
        Offer__c second = OfferService.submitOffer(property.Id, 'B', 830000);
        OfferService.acceptOffer(first.Id);
        for (Integer i = 0; i < 2; i++) {
            try {
                if (i == 0) {
                    OfferService.acceptOffer(second.Id);
                } else {
                    OfferService.rejectOffer(second.Id);
                }
                Assert.fail('Property is under agreement');
            } catch (OfferService.OfferException e) {
                Assert.isTrue(e.getMessage().contains('Under Agreement'));
            }
        }
    }

    @isTest
    static void reopenedPropertyWithAcceptedOfferCannotAcceptAgain() {
        Property__c property = createProperty('Available');
        Offer__c first = OfferService.submitOffer(property.Id, 'A', 840000);
        OfferService.acceptOffer(first.Id);
        update new Property__c(Id = property.Id, Status__c = 'Available');
        Offer__c second = OfferService.submitOffer(property.Id, 'B', 830000);
        try {
            OfferService.acceptOffer(second.Id);
            Assert.fail('Already has an accepted offer');
        } catch (OfferService.OfferException e) {
            Assert.isTrue(e.getMessage().contains('already has an accepted'));
        }
        Assert.areEqual('Submitted', reload(second.Id).Status__c);
    }

    @isTest
    static void rejectOnlyOpenOffers() {
        Property__c property = createProperty('Available');
        Offer__c offer = OfferService.submitOffer(property.Id, 'A', 700000);
        OfferService.rejectOffer(offer.Id);
        Assert.areEqual('Rejected', reload(offer.Id).Status__c);
        try {
            OfferService.rejectOffer(offer.Id);
            Assert.fail('Already rejected');
        } catch (OfferService.OfferException e) {
            Assert.isTrue(e.getMessage().contains('open offers'));
        }
        try {
            OfferService.acceptOffer(offer.Id);
            Assert.fail('Rejected cannot be accepted');
        } catch (OfferService.OfferException e) {
            Assert.isTrue(e.getMessage().contains('submitted or approved'));
        }
    }

    @isTest
    static void unknownOfferThrows() {
        Property__c property = createProperty('Available');
        Offer__c offer = OfferService.submitOffer(property.Id, 'A', 800000);
        Id offerId = offer.Id;
        delete offer;
        try {
            OfferService.rejectOffer(offerId);
            Assert.fail('Expected not found');
        } catch (OfferService.OfferException e) {
            Assert.areEqual('Offer not found.', e.getMessage());
        }
    }

    @isTest
    static void priceRiseRequiresApprovalAgain() {
        Property__c property = createProperty('Available');
        User broker = createUser(true);
        System.runAs(broker) {
            Offer__c offer = OfferService.submitOffer(property.Id, 'A', 800000);
            update new Property__c(Id = property.Id, Price__c = 900000);
            try {
                OfferService.acceptOffer(offer.Id);
                Assert.fail('Discount is now over the threshold');
            } catch (OfferService.OfferException e) {
                Assert.isTrue(e.getMessage().contains('asking price changed'));
            }
            OfferService.approveOffer(offer.Id);
            Offer__c approved = reload(offer.Id);
            Assert.areEqual('Approved', approved.Status__c);
            Assert.areEqual(11.1, approved.Approved_Percent_Below__c);

            update new Property__c(Id = property.Id, Price__c = 1000000);
            try {
                OfferService.acceptOffer(offer.Id);
                Assert.fail('Discount is past the approved level');
            } catch (OfferService.OfferException e) {
                Assert.isTrue(e.getMessage().contains('asking price changed'));
            }
            OfferService.approveOffer(offer.Id);
            Assert.areEqual(20.0, reload(offer.Id).Approved_Percent_Below__c);
            OfferService.acceptOffer(offer.Id);
            Assert.areEqual('Accepted', reload(offer.Id).Status__c);
        }
    }

    @isTest
    static void triggerBlocksDirectEdits() {
        Property__c property = createProperty('Available');
        Offer__c offer = OfferService.submitOffer(property.Id, 'A', 720000);
        List<Offer__c> directEdits = new List<Offer__c>{
            new Offer__c(Id = offer.Id, Status__c = 'Approved'),
            new Offer__c(Id = offer.Id, Status__c = 'Accepted'),
            new Offer__c(Id = offer.Id, Amount__c = 840000),
            new Offer__c(Id = offer.Id, Percent_Below_Asking__c = 1),
            new Offer__c(Id = offer.Id, Approved_Percent_Below__c = 50),
            new Offer__c(Id = offer.Id, Buyer_Name__c = 'Someone Else')
        };
        for (Offer__c edit : directEdits) {
            try {
                update edit;
                Assert.fail('Direct edit should be blocked: ' + edit);
            } catch (DmlException e) {
                Assert.isTrue(
                    errorOf(e).contains('Offer status') ||
                    errorOf(e).contains('cannot be changed')
                );
            }
        }
        Offer__c unchanged = reload(offer.Id);
        Assert.areEqual('Needs Approval', unchanged.Status__c);
        Assert.areEqual(720000, unchanged.Amount__c);
    }

    @isTest
    static void triggerDerivesFieldsOnDirectInsert() {
        Property__c property = createProperty('Available');
        Offer__c offer = new Offer__c(
            Property__c = property.Id,
            Buyer_Name__c = 'Direct',
            Amount__c = 700000,
            Status__c = 'Accepted',
            Percent_Below_Asking__c = 0,
            Approved_Percent_Below__c = 99
        );
        insert offer;
        Offer__c saved = reload(offer.Id);
        Assert.areEqual('Needs Approval', saved.Status__c);
        Assert.areEqual(17.2, saved.Percent_Below_Asking__c);
        Assert.isNull(saved.Approved_Percent_Below__c);

        Property__c closed = createProperty('Closed');
        List<Offer__c> invalid = new List<Offer__c>{
            new Offer__c(
                Property__c = closed.Id,
                Buyer_Name__c = 'Closed',
                Amount__c = 800000
            ),
            new Offer__c(
                Property__c = property.Id,
                Buyer_Name__c = 'Zero',
                Amount__c = 0
            )
        };
        List<Database.SaveResult> results = Database.insert(invalid, false);
        Assert.isFalse(results[0].isSuccess());
        Assert.isTrue(
            results[0].getErrors()[0].getMessage().contains('Closed')
        );
        Assert.isFalse(results[1].isSuccess());
        Assert.isTrue(
            results[1].getErrors()[0].getMessage().contains('greater than zero')
        );
    }
}
