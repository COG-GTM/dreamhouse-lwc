@isTest
public class OfferServiceTest {
    private static final Decimal ASKING_PRICE = 845000;

    @testSetup
    static void setup() {
        insert new List<Property__c>{
            new Property__c(
                Name = 'Open House',
                Price__c = ASKING_PRICE,
                Status__c = 'Available'
            ),
            new Property__c(
                Name = 'Closed House',
                Price__c = ASKING_PRICE,
                Status__c = 'Closed'
            ),
            new Property__c(
                Name = 'Agreed House',
                Price__c = ASKING_PRICE,
                Status__c = 'Under Agreement'
            ),
            new Property__c(
                Name = 'Contracted House',
                Price__c = ASKING_PRICE,
                Status__c = 'Contracted'
            ),
            new Property__c(Name = 'Unpriced House', Status__c = 'Available')
        };
        System.runAs(new User(Id = UserInfo.getUserId())) {
            createUser('agent', false);
            createUser('broker', true);
        }
    }

    public static User createUser(String alias, Boolean isBroker) {
        Profile standardProfile = [
            SELECT Id
            FROM Profile
            WHERE Name = 'Standard User'
            LIMIT 1
        ];
        User user = new User(
            Alias = alias,
            Email = alias + '@dreamhouse-offers.test',
            EmailEncodingKey = 'UTF-8',
            LastName = alias,
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            ProfileId = standardProfile.Id,
            TimeZoneSidKey = 'America/Los_Angeles',
            UserName = alias +
                '.' +
                DateTime.now().getTime() +
                '@dreamhouse-offers.test'
        );
        insert user;

        Set<String> permissionSetNames = new Set<String>{ 'dreamhouse' };
        if (isBroker) {
            permissionSetNames.add('Dreamhouse_Broker');
        }
        List<PermissionSetAssignment> assignments = new List<PermissionSetAssignment>();
        for (PermissionSet permissionSet : [
            SELECT Id
            FROM PermissionSet
            WHERE Name IN :permissionSetNames
        ]) {
            assignments.add(
                new PermissionSetAssignment(
                    AssigneeId = user.Id,
                    PermissionSetId = permissionSet.Id
                )
            );
        }
        insert assignments;
        return user;
    }

    public static User getUser(String alias) {
        return [
            SELECT Id
            FROM User
            WHERE Email = :(alias + '@dreamhouse-offers.test')
            LIMIT 1
        ];
    }

    private static Id propertyId(String name) {
        return [SELECT Id FROM Property__c WHERE Name = :name LIMIT 1].Id;
    }

    private static Offer__c reload(Id offerId) {
        return [
            SELECT Id, Status__c, Amount__c, Percent_Below_Asking__c
            FROM Offer__c
            WHERE Id = :offerId
        ];
    }

    private static String submitExpectingError(
        Id propertyId,
        String buyer,
        Decimal amount
    ) {
        try {
            OfferService.submitOffer(propertyId, buyer, amount);
        } catch (OfferService.OfferException e) {
            return e.getMessage();
        }
        Assert.fail('Expected the offer to be rejected');
        return null;
    }

    @isTest
    static void calculatesPercentBelowAskingToOneDecimal() {
        Assert.areEqual(
            14.8,
            OfferService.calculatePercentBelowAsking(845000, 720000)
        );
        Assert.areEqual(
            3.0,
            OfferService.calculatePercentBelowAsking(845000, 820000)
        );
        Assert.areEqual(
            10.0,
            OfferService.calculatePercentBelowAsking(845000, 760500)
        );
        Assert.areEqual(
            -5.0,
            OfferService.calculatePercentBelowAsking(100000, 105000)
        );
        Assert.isNull(OfferService.calculatePercentBelowAsking(null, 1));
        Assert.isNull(OfferService.calculatePercentBelowAsking(0, 1));
        Assert.isNull(OfferService.calculatePercentBelowAsking(1, null));
        Assert.isFalse(OfferService.needsApproval(10.0));
        Assert.isTrue(OfferService.needsApproval(10.1));
        Assert.isFalse(OfferService.needsApproval(null));
    }

    @isTest
    static void offerWithinTenPercentIsSubmitted() {
        System.runAs(getUser('agent')) {
            Offer__c offer = OfferService.submitOffer(
                propertyId('Open House'),
                '  Jane Buyer ',
                820000
            );
            Assert.areEqual(OfferService.STATUS_SUBMITTED, offer.Status__c);
            Assert.areEqual(3.0, offer.Percent_Below_Asking__c);
            Assert.areEqual('Jane Buyer', offer.Buyer_Name__c);
        }
    }

    @isTest
    static void offerExactlyTenPercentBelowIsSubmitted() {
        System.runAs(getUser('agent')) {
            Offer__c offer = OfferService.submitOffer(
                propertyId('Open House'),
                'Edge Buyer',
                760500
            );
            Assert.areEqual(OfferService.STATUS_SUBMITTED, offer.Status__c);
        }
    }

    @isTest
    static void offerMoreThanTenPercentBelowNeedsApproval() {
        System.runAs(getUser('agent')) {
            Offer__c offer = OfferService.submitOffer(
                propertyId('Open House'),
                'Sam Lowball',
                720000
            );
            Assert.areEqual(
                OfferService.STATUS_NEEDS_APPROVAL,
                offer.Status__c
            );
            Assert.areEqual(14.8, offer.Percent_Below_Asking__c);
            Assert.areEqual(
                1,
                OfferService.getOffers(propertyId('Open House')).size()
            );
        }
    }

    @isTest
    static void directInsertCannotChooseStatusOrPercent() {
        Offer__c offer = new Offer__c(
            Property__c = propertyId('Open House'),
            Buyer_Name__c = 'Sneaky',
            Amount__c = 500000,
            Status__c = OfferService.STATUS_APPROVED,
            Percent_Below_Asking__c = 0
        );
        insert offer;
        Offer__c saved = reload(offer.Id);
        Assert.areEqual(OfferService.STATUS_NEEDS_APPROVAL, saved.Status__c);
        Assert.areEqual(40.8, saved.Percent_Below_Asking__c);
    }

    @isTest
    static void invalidSubmissionsAreBlocked() {
        System.runAs(getUser('agent')) {
            Id openId = propertyId('Open House');
            Assert.isTrue(
                submitExpectingError(openId, ' ', 800000).contains('buyer')
            );
            Assert.isTrue(
                submitExpectingError(openId, 'Zero', 0).contains('zero')
            );
            Assert.isTrue(
                submitExpectingError(openId, 'Negative', -1).contains('zero')
            );
            Assert.isTrue(
                submitExpectingError(propertyId('Closed House'), 'Late', 800000)
                    .contains('Closed')
            );
            Assert.isTrue(
                submitExpectingError(propertyId('Agreed House'), 'Late', 800000)
                    .contains('Under Agreement')
            );
            Assert.isTrue(
                submitExpectingError(
                        propertyId('Contracted House'),
                        'Late',
                        800000
                    )
                    .contains('Contracted')
            );
            Assert.isTrue(
                submitExpectingError(
                        propertyId('Unpriced House'),
                        'Early',
                        800000
                    )
                    .contains('asking price')
            );
        }
    }

    @isTest
    static void agentCannotApproveButBrokerCan() {
        Id openId = propertyId('Open House');
        Offer__c offer;
        System.runAs(getUser('agent')) {
            offer = OfferService.submitOffer(openId, 'Sam Lowball', 720000);
            Assert.isFalse(OfferService.canApprove());
            try {
                OfferService.approveOffer(offer.Id);
                Assert.fail('Agent should not be able to approve');
            } catch (OfferService.OfferException e) {
                Assert.isTrue(e.getMessage().contains('Approve Offers'));
            }
        }
        System.runAs(getUser('broker')) {
            Assert.isTrue(OfferService.canApprove());
            OfferService.approveOffer(offer.Id);
        }
        Assert.areEqual(
            OfferService.STATUS_APPROVED,
            reload(offer.Id).Status__c
        );
    }

    @isTest
    static void onlyNeedsApprovalOffersCanBeApproved() {
        System.runAs(getUser('broker')) {
            Offer__c offer = OfferService.submitOffer(
                propertyId('Open House'),
                'Jane Buyer',
                820000
            );
            try {
                OfferService.approveOffer(offer.Id);
                Assert.fail('Submitted offers do not need approval');
            } catch (OfferService.OfferException e) {
                Assert.isTrue(e.getMessage().contains('need approval'));
            }
        }
    }

    @isTest
    static void needsApprovalOfferCannotBeAcceptedUntilApproved() {
        Id openId = propertyId('Open House');
        System.runAs(getUser('broker')) {
            Offer__c jane = OfferService.submitOffer(
                openId,
                'Jane Buyer',
                820000
            );
            Offer__c sam = OfferService.submitOffer(
                openId,
                'Sam Lowball',
                720000
            );
            try {
                OfferService.acceptOffer(sam.Id);
                Assert.fail('Needs Approval offers cannot be accepted');
            } catch (OfferService.OfferException e) {
                Assert.isTrue(e.getMessage().contains('must be approved'));
            }

            OfferService.approveOffer(sam.Id);
            OfferService.acceptOffer(sam.Id);

            Assert.areEqual(
                OfferService.STATUS_ACCEPTED,
                reload(sam.Id).Status__c
            );
            Assert.areEqual(
                OfferService.STATUS_REJECTED,
                reload(jane.Id).Status__c
            );
        }
        Property__c property = [
            SELECT Status__c, Date_Agreement__c
            FROM Property__c
            WHERE Id = :openId
        ];
        Assert.areEqual('Under Agreement', property.Status__c);
        Assert.areEqual(Date.today(), property.Date_Agreement__c);
    }

    @isTest
    static void acceptRefusesPropertyAlreadyUnderAgreement() {
        Id openId = propertyId('Open House');
        Offer__c offer = OfferService.submitOffer(openId, 'Jane Buyer', 820000);
        update new Property__c(Id = openId, Status__c = 'Under Agreement');
        try {
            OfferService.acceptOffer(offer.Id);
            Assert.fail('Property is already under agreement');
        } catch (OfferService.OfferException e) {
            Assert.isTrue(e.getMessage().contains('already Under Agreement'));
        }
        Assert.areEqual(
            OfferService.STATUS_SUBMITTED,
            reload(offer.Id).Status__c
        );
    }

    @isTest
    static void acceptRefusesContractedPropertyAndKeepsItsDate() {
        Id openId = propertyId('Open House');
        Offer__c offer = OfferService.submitOffer(openId, 'Jane Buyer', 820000);
        Date contractDate = Date.today().addDays(-3);
        update new Property__c(
            Id = openId,
            Status__c = 'Contracted',
            Date_Agreement__c = contractDate
        );
        try {
            OfferService.acceptOffer(offer.Id);
            Assert.fail('Property is already contracted');
        } catch (OfferService.OfferException e) {
            Assert.isTrue(e.getMessage().contains('already Contracted'));
        }
        Property__c property = [
            SELECT Status__c, Date_Agreement__c
            FROM Property__c
            WHERE Id = :openId
        ];
        Assert.areEqual('Contracted', property.Status__c);
        Assert.areEqual(contractDate, property.Date_Agreement__c);
    }

    @isTest
    static void rejectedOffersAreFinal() {
        System.runAs(getUser('agent')) {
            Offer__c offer = OfferService.submitOffer(
                propertyId('Open House'),
                'Jane Buyer',
                820000
            );
            OfferService.rejectOffer(offer.Id);
            Assert.areEqual(
                OfferService.STATUS_REJECTED,
                reload(offer.Id).Status__c
            );
            try {
                OfferService.rejectOffer(offer.Id);
                Assert.fail('Already rejected');
            } catch (OfferService.OfferException e) {
                Assert.isTrue(e.getMessage().contains('open offers'));
            }
            try {
                OfferService.acceptOffer(offer.Id);
                Assert.fail('Rejected offers cannot be accepted');
            } catch (OfferService.OfferException e) {
                Assert.isTrue(e.getMessage().contains('open offers'));
            }
        }
    }

    @isTest
    static void statusAmountAndPercentCannotBeEditedDirectly() {
        Offer__c offer = OfferService.submitOffer(
            propertyId('Open House'),
            'Sam Lowball',
            720000
        );
        List<Offer__c> edits = new List<Offer__c>{
            new Offer__c(
                Id = offer.Id,
                Status__c = OfferService.STATUS_APPROVED
            ),
            new Offer__c(Id = offer.Id, Amount__c = 800000),
            new Offer__c(Id = offer.Id, Percent_Below_Asking__c = 1)
        };
        for (Offer__c edit : edits) {
            try {
                update edit;
                Assert.fail('Direct edit should be blocked');
            } catch (DmlException e) {
                Assert.isTrue(
                    e.getDmlMessage(0).contains('cannot be changed') ||
                    e.getDmlMessage(0).contains('can only be changed')
                );
            }
        }
        Offer__c saved = reload(offer.Id);
        Assert.areEqual(OfferService.STATUS_NEEDS_APPROVAL, saved.Status__c);
        Assert.areEqual(720000, saved.Amount__c);
    }

    @isTest
    static void missingOfferIsReported() {
        Offer__c offer = OfferService.submitOffer(
            propertyId('Open House'),
            'Jane Buyer',
            820000
        );
        delete offer;
        try {
            OfferService.rejectOffer(offer.Id);
            Assert.fail('Offer was deleted');
        } catch (OfferService.OfferException e) {
            Assert.areEqual('Offer not found.', e.getMessage());
        }
    }
}
