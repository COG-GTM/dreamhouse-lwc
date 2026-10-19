@isTest
private class OfferServiceTest {
    @testSetup
    static void setup() {
        OfferTestFactory.createUsersAndProperty();
    }

    @isTest
    static void percentBelowAskingRoundsHalfUpToOneDecimal() {
        Assert.areEqual(14.8, OfferService.percentBelowAsking(845000, 720000));
        Assert.areEqual(3.0, OfferService.percentBelowAsking(845000, 820000));
        Assert.areEqual(10.1, OfferService.percentBelowAsking(100000, 89950));
        Assert.areEqual(10.0, OfferService.percentBelowAsking(100000, 89951));
        Assert.areEqual(-10.0, OfferService.percentBelowAsking(100000, 110000));
        Assert.isFalse(OfferService.requiresApproval(10.0));
        Assert.isTrue(OfferService.requiresApproval(10.1));
    }

    @isTest
    static void smallDiscountIsSubmitted() {
        Property__c property = OfferTestFactory.property();
        Offer__c offer;
        System.runAs(OfferTestFactory.agent()) {
            Test.startTest();
            offer = OfferService.submitOffer(
                property.Id,
                ' Jane Buyer ',
                820000
            );
            Test.stopTest();
        }
        Offer__c saved = OfferTestFactory.offer(offer.Id);
        Assert.areEqual('Jane Buyer', saved.Buyer_Name__c);
        Assert.areEqual(3.0, saved.Percent_Below_Asking__c);
        Assert.areEqual(OfferService.STATUS_SUBMITTED, saved.Status__c);
    }

    @isTest
    static void largeDiscountNeedsApproval() {
        Property__c property = OfferTestFactory.property();
        Offer__c offer;
        System.runAs(OfferTestFactory.agent()) {
            offer = OfferService.submitOffer(
                property.Id,
                'Sam Lowball',
                720000
            );
        }
        Offer__c saved = OfferTestFactory.offer(offer.Id);
        Assert.areEqual(14.8, saved.Percent_Below_Asking__c);
        Assert.areEqual(OfferService.STATUS_NEEDS_APPROVAL, saved.Status__c);
    }

    @isTest
    static void submitRejectsInvalidInput() {
        Property__c property = OfferTestFactory.property();
        System.runAs(OfferTestFactory.agent()) {
            assertSubmitFails(property.Id, ' ', 800000, 'buyer name');
            assertSubmitFails(property.Id, 'Jane', 0, 'greater than zero');
            assertSubmitFails(property.Id, 'Jane', -5, 'greater than zero');
            assertSubmitFails(property.Id, 'Jane', null, 'greater than zero');
        }
    }

    @isTest
    static void submitRejectsClosedProperties() {
        Property__c property = OfferTestFactory.property();
        for (String status : OfferService.CLOSED_PROPERTY_STATUSES) {
            update new Property__c(Id = property.Id, Status__c = status);
            System.runAs(OfferTestFactory.agent()) {
                assertSubmitFails(property.Id, 'Jane', 800000, status);
            }
        }
        Assert.areEqual(0, [SELECT COUNT() FROM Offer__c]);
    }

    @isTest
    static void submitRequiresAskingPrice() {
        Property__c property = OfferTestFactory.property();
        update new Property__c(Id = property.Id, Price__c = null);
        System.runAs(OfferTestFactory.agent()) {
            assertSubmitFails(property.Id, 'Jane', 800000, 'no asking price');
        }
    }

    @isTest
    static void agentCannotApproveButBrokerCan() {
        Property__c property = OfferTestFactory.property();
        Offer__c offer;
        System.runAs(OfferTestFactory.agent()) {
            offer = OfferService.submitOffer(
                property.Id,
                'Sam Lowball',
                720000
            );
            try {
                OfferService.approveOffer(offer.Id);
                Assert.fail('Agent should not be able to approve');
            } catch (OfferService.OfferException e) {
                Assert.isTrue(e.getMessage().contains('Approve Offers'));
            }
        }
        System.runAs(OfferTestFactory.broker()) {
            OfferService.approveOffer(offer.Id);
        }
        Assert.areEqual(
            OfferService.STATUS_APPROVED,
            OfferTestFactory.offer(offer.Id).Status__c
        );
    }

    @isTest
    static void approveOnlyAppliesToOffersNeedingApproval() {
        Property__c property = OfferTestFactory.property();
        System.runAs(OfferTestFactory.broker()) {
            Offer__c offer = OfferService.submitOffer(
                property.Id,
                'Jane',
                820000
            );
            try {
                OfferService.approveOffer(offer.Id);
                Assert.fail('Submitted offer should not be approvable');
            } catch (OfferService.OfferException e) {
                Assert.isTrue(e.getMessage().contains('need approval'));
            }
        }
    }

    @isTest
    static void needsApprovalOfferCannotBeAccepted() {
        Property__c property = OfferTestFactory.property();
        System.runAs(OfferTestFactory.agent()) {
            Offer__c offer = OfferService.submitOffer(
                property.Id,
                'Sam',
                720000
            );
            try {
                OfferService.acceptOffer(offer.Id);
                Assert.fail('Needs Approval offer should not be acceptable');
            } catch (OfferService.OfferException e) {
                Assert.isTrue(e.getMessage().contains('needs broker approval'));
            }
        }
        Assert.areEqual('Available', OfferTestFactory.property().Status__c);
    }

    @isTest
    static void acceptingApprovedOfferRejectsOthersAndPutsPropertyUnderAgreement() {
        Property__c property = OfferTestFactory.property();
        Offer__c jane;
        Offer__c sam;
        System.runAs(OfferTestFactory.agent()) {
            jane = OfferService.submitOffer(property.Id, 'Jane Buyer', 820000);
            sam = OfferService.submitOffer(property.Id, 'Sam Lowball', 720000);
        }
        System.runAs(OfferTestFactory.broker()) {
            OfferService.approveOffer(sam.Id);
        }
        System.runAs(OfferTestFactory.agent()) {
            Test.startTest();
            OfferService.acceptOffer(sam.Id);
            Test.stopTest();
        }
        Assert.areEqual(
            OfferService.STATUS_ACCEPTED,
            OfferTestFactory.offer(sam.Id).Status__c
        );
        Assert.areEqual(
            OfferService.STATUS_REJECTED,
            OfferTestFactory.offer(jane.Id).Status__c
        );
        Property__c updated = OfferTestFactory.property();
        Assert.areEqual('Under Agreement', updated.Status__c);
        Assert.areEqual(Date.today(), updated.Date_Agreement__c);
    }

    @isTest
    static void acceptRefusesWhenPropertyAlreadyUnderAgreement() {
        Property__c property = OfferTestFactory.property();
        System.runAs(OfferTestFactory.agent()) {
            Offer__c offer = OfferService.submitOffer(
                property.Id,
                'Jane',
                820000
            );
            update new Property__c(
                Id = property.Id,
                Status__c = 'Under Agreement'
            );
            try {
                OfferService.acceptOffer(offer.Id);
                Assert.fail(
                    'Accept should fail on an Under Agreement property'
                );
            } catch (OfferService.OfferException e) {
                Assert.isTrue(
                    e.getMessage().contains('no longer taking offers')
                );
            }
        }
    }

    @isTest
    static void acceptRechecksDiscountAgainstCurrentAskingPrice() {
        Property__c property = OfferTestFactory.property();
        System.runAs(OfferTestFactory.agent()) {
            Offer__c offer = OfferService.submitOffer(
                property.Id,
                'Jane',
                820000
            );
            update new Property__c(Id = property.Id, Price__c = 1000000);
            try {
                OfferService.acceptOffer(offer.Id);
                Assert.fail('Accept should re-check the discount');
            } catch (OfferService.OfferException e) {
                Assert.isTrue(e.getMessage().contains('18.0% below asking'));
            }
        }
    }

    @isTest
    static void rejectedOfferCannotBeAcceptedOrRejectedAgain() {
        Property__c property = OfferTestFactory.property();
        System.runAs(OfferTestFactory.agent()) {
            Offer__c offer = OfferService.submitOffer(
                property.Id,
                'Jane',
                820000
            );
            OfferService.rejectOffer(offer.Id);
            Assert.areEqual(
                OfferService.STATUS_REJECTED,
                OfferTestFactory.offer(offer.Id).Status__c
            );
            try {
                OfferService.acceptOffer(offer.Id);
                Assert.fail('Rejected offer should not be acceptable');
            } catch (OfferService.OfferException e) {
                Assert.isTrue(e.getMessage().contains('submitted or approved'));
            }
            try {
                OfferService.rejectOffer(offer.Id);
                Assert.fail('Rejected offer should not be rejectable');
            } catch (OfferService.OfferException e) {
                Assert.isTrue(e.getMessage().contains('open offers'));
            }
        }
    }

    @isTest
    static void directStatusAmountAndPercentEditsAreBlocked() {
        Property__c property = OfferTestFactory.property();
        System.runAs(OfferTestFactory.agent()) {
            Offer__c offer = OfferService.submitOffer(
                property.Id,
                'Sam',
                720000
            );
            assertUpdateFails(
                new Offer__c(
                    Id = offer.Id,
                    Status__c = OfferService.STATUS_APPROVED
                ),
                'Approve, Accept or Reject'
            );
            assertUpdateFails(
                new Offer__c(Id = offer.Id, Amount__c = 800000),
                'amount cannot be changed'
            );
            assertUpdateFails(
                new Offer__c(Id = offer.Id, Percent_Below_Asking__c = 1),
                'cannot be changed after submission'
            );
            update new Offer__c(Id = offer.Id, Buyer_Name__c = 'Sam Lowball');
        }
        Assert.areEqual(
            OfferService.STATUS_NEEDS_APPROVAL,
            [SELECT Status__c FROM Offer__c].Status__c
        );
    }

    @isTest
    static void directInsertIsBlocked() {
        Property__c property = OfferTestFactory.property();
        try {
            insert new Offer__c(
                Property__c = property.Id,
                Buyer_Name__c = 'Sneaky',
                Amount__c = 100,
                Status__c = OfferService.STATUS_ACCEPTED
            );
            Assert.fail('Direct insert should be blocked');
        } catch (DmlException e) {
            Assert.isTrue(e.getDmlMessage(0).contains('Offers card'));
        }
    }

    @isTest
    static void offerContextReflectsUserAndProperty() {
        Property__c property = OfferTestFactory.property();
        System.runAs(OfferTestFactory.agent()) {
            OfferService.submitOffer(property.Id, 'Jane', 820000);
            OfferService.OfferContext context = OfferService.getOfferContext(
                property.Id
            );
            Assert.areEqual(845000, context.askingPrice);
            Assert.areEqual('Available', context.propertyStatus);
            Assert.isTrue(context.propertyOpen);
            Assert.isFalse(context.canApprove);
            Assert.areEqual(10, context.approvalThreshold);
            Assert.areEqual(1, context.offers.size());
        }
        System.runAs(OfferTestFactory.broker()) {
            Assert.isTrue(OfferService.getOfferContext(property.Id).canApprove);
        }
    }

    @isTest
    static void unknownOfferAndPropertyAreReported() {
        Property__c property = OfferTestFactory.property();
        Id missingOffer;
        System.runAs(OfferTestFactory.agent()) {
            Offer__c offer = OfferService.submitOffer(
                property.Id,
                'Jane',
                820000
            );
            missingOffer = offer.Id;
        }
        delete [SELECT Id FROM Offer__c];
        delete property;
        System.runAs(OfferTestFactory.agent()) {
            try {
                OfferService.rejectOffer(missingOffer);
                Assert.fail('Missing offer should fail');
            } catch (OfferService.OfferException e) {
                Assert.areEqual('Offer not found.', e.getMessage());
            }
            assertSubmitFails(
                property.Id,
                'Jane',
                820000,
                'Property not found'
            );
        }
    }

    private static void assertSubmitFails(
        Id propertyId,
        String buyer,
        Decimal amount,
        String expected
    ) {
        try {
            OfferService.submitOffer(propertyId, buyer, amount);
            Assert.fail('Expected submit to fail with: ' + expected);
        } catch (OfferService.OfferException e) {
            Assert.isTrue(
                e.getMessage().containsIgnoreCase(expected),
                e.getMessage()
            );
        }
    }

    private static void assertUpdateFails(Offer__c offer, String expected) {
        try {
            update offer;
            Assert.fail('Expected update to fail with: ' + expected);
        } catch (DmlException e) {
            Assert.isTrue(
                e.getDmlMessage(0).contains(expected),
                e.getDmlMessage(0)
            );
        }
    }
}
