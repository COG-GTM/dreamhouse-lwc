@isTest
private class OfferServiceTest {
    @TestSetup
    static void setup() {
        OfferTestFactory.createUsersAndProperty();
    }

    private static String submitError(
        Id propertyId,
        String buyer,
        Decimal amount
    ) {
        try {
            OfferService.submit(propertyId, buyer, amount);
        } catch (OfferService.OfferException e) {
            return e.getMessage();
        }
        return null;
    }

    private static void setPropertyStatus(String status) {
        update new Property__c(
            Id = OfferTestFactory.property().Id,
            Status__c = status
        );
    }

    @isTest
    static void percentBelowAskingRoundsToOneDecimal() {
        Assert.areEqual(14.8, OfferService.percentBelowAsking(845000, 720000));
        Assert.areEqual(3.0, OfferService.percentBelowAsking(845000, 820000));
        Assert.areEqual(10.0, OfferService.percentBelowAsking(845000, 760500));
        Assert.areEqual(-5.0, OfferService.percentBelowAsking(845000, 887250));
        Assert.isNull(OfferService.percentBelowAsking(0, 100));
        Assert.isNull(OfferService.percentBelowAsking(null, 100));
        Assert.isFalse(OfferService.needsApproval(10.0));
        Assert.isTrue(OfferService.needsApproval(10.1));
        Assert.isFalse(OfferService.needsApproval(null));
    }

    @isTest
    static void submitAtOrUnderThresholdIsSubmitted() {
        Id propertyId = OfferTestFactory.property().Id;
        System.runAs(OfferTestFactory.agent()) {
            Offer__c jane = OfferService.submit(
                propertyId,
                ' Jane Buyer ',
                820000
            );
            Offer__c edge = OfferService.submit(
                propertyId,
                'Edge Case',
                760500
            );

            Offer__c saved = OfferTestFactory.offer(jane.Id);
            Assert.areEqual(OfferService.STATUS_SUBMITTED, saved.Status__c);
            Assert.areEqual(3.0, saved.Percent_Below_Asking__c);
            Assert.areEqual('Jane Buyer', jane.Buyer_Name__c);
            Assert.areEqual(
                OfferService.STATUS_SUBMITTED,
                OfferTestFactory.offer(edge.Id).Status__c
            );
            Assert.areEqual(2, OfferService.getOffers(propertyId).size());
        }
    }

    @isTest
    static void submitOverThresholdNeedsApproval() {
        Id propertyId = OfferTestFactory.property().Id;
        System.runAs(OfferTestFactory.agent()) {
            Offer__c sam = OfferService.submit(
                propertyId,
                'Sam Lowball',
                720000
            );
            Offer__c saved = OfferTestFactory.offer(sam.Id);
            Assert.areEqual(
                OfferService.STATUS_NEEDS_APPROVAL,
                saved.Status__c
            );
            Assert.areEqual(14.8, saved.Percent_Below_Asking__c);
        }
    }

    @isTest
    static void submitRejectsInvalidInput() {
        Id propertyId = OfferTestFactory.property().Id;
        System.runAs(OfferTestFactory.agent()) {
            Assert.areEqual(
                'Enter the buyer name.',
                submitError(propertyId, ' ', 1000)
            );
            String amountError = 'The offer amount must be more than $0.';
            Assert.areEqual(amountError, submitError(propertyId, 'A', 0));
            Assert.areEqual(amountError, submitError(propertyId, 'A', -5));
            Assert.areEqual(amountError, submitError(propertyId, 'A', null));
        }
        Assert.areEqual(0, [SELECT COUNT() FROM Offer__c]);
    }

    @isTest
    static void submitNeedsAnExistingPricedProperty() {
        Property__c unpriced = new Property__c(
            Name = 'Unpriced',
            Status__c = 'Available'
        );
        Property__c gone = new Property__c(Name = 'Gone', Price__c = 1);
        insert new List<Property__c>{ unpriced, gone };
        delete gone;
        System.runAs(OfferTestFactory.agent()) {
            Assert.areEqual(
                'Property not found.',
                submitError(gone.Id, 'A', 1000)
            );
            Assert.isTrue(
                submitError(unpriced.Id, 'A', 1000).contains('no asking price')
            );
        }
    }

    @isTest
    static void submitBlockedOnUnderAgreementOrClosedProperty() {
        Id propertyId = OfferTestFactory.property().Id;
        for (String status : new List<String>{ 'Under Agreement', 'Closed' }) {
            setPropertyStatus(status);
            System.runAs(OfferTestFactory.agent()) {
                Assert.areEqual(
                    'This property is ' + status + ' and is not taking offers.',
                    submitError(propertyId, 'Late Buyer', 800000)
                );
            }
        }
        Assert.areEqual(0, [SELECT COUNT() FROM Offer__c]);
    }

    @isTest
    static void onlyBrokersCanApprove() {
        Id propertyId = OfferTestFactory.property().Id;
        Offer__c sam;
        System.runAs(OfferTestFactory.agent()) {
            Assert.isFalse(OfferService.canApprove());
            sam = OfferService.submit(propertyId, 'Sam Lowball', 720000);
            try {
                OfferService.approve(sam.Id);
                Assert.fail('Agent should not be able to approve');
            } catch (OfferService.OfferException e) {
                Assert.isTrue(e.getMessage().contains('Approve Offers'));
            }
        }
        Assert.areEqual(
            OfferService.STATUS_NEEDS_APPROVAL,
            OfferTestFactory.offer(sam.Id).Status__c
        );
        System.runAs(OfferTestFactory.broker()) {
            Assert.isTrue(OfferService.canApprove());
            OfferService.approve(sam.Id);
        }
        Assert.areEqual(
            OfferService.STATUS_APPROVED,
            OfferTestFactory.offer(sam.Id).Status__c
        );
    }

    @isTest
    static void approveOnlyAppliesToOffersThatNeedApproval() {
        Id propertyId = OfferTestFactory.property().Id;
        System.runAs(OfferTestFactory.broker()) {
            Offer__c jane = OfferService.submit(
                propertyId,
                'Jane Buyer',
                820000
            );
            try {
                OfferService.approve(jane.Id);
                Assert.fail('Submitted offers do not need approval');
            } catch (OfferService.OfferException e) {
                Assert.areEqual(
                    'Only offers that need approval can be approved.',
                    e.getMessage()
                );
            }
        }
    }

    @isTest
    static void needsApprovalOfferCannotBeAccepted() {
        Id propertyId = OfferTestFactory.property().Id;
        System.runAs(OfferTestFactory.broker()) {
            Offer__c sam = OfferService.submit(
                propertyId,
                'Sam Lowball',
                720000
            );
            try {
                OfferService.accept(sam.Id);
                Assert.fail('Needs Approval offers must be approved first');
            } catch (OfferService.OfferException e) {
                Assert.isTrue(e.getMessage().contains('must approve'));
            }
        }
        Assert.areEqual('Available', OfferTestFactory.property().Status__c);
    }

    @isTest
    static void acceptRejectsOtherOpenOffersAndPutsPropertyUnderAgreement() {
        Id propertyId = OfferTestFactory.property().Id;
        Offer__c jane;
        Offer__c sam;
        System.runAs(OfferTestFactory.agent()) {
            jane = OfferService.submit(propertyId, 'Jane Buyer', 820000);
            sam = OfferService.submit(propertyId, 'Sam Lowball', 720000);
        }
        System.runAs(OfferTestFactory.broker()) {
            OfferService.approve(sam.Id);
        }
        System.runAs(OfferTestFactory.agent()) {
            OfferService.accept(sam.Id);
        }
        Assert.areEqual(
            OfferService.STATUS_ACCEPTED,
            OfferTestFactory.offer(sam.Id).Status__c
        );
        Assert.areEqual(
            OfferService.STATUS_REJECTED,
            OfferTestFactory.offer(jane.Id).Status__c
        );
        Property__c property = OfferTestFactory.property();
        Assert.areEqual('Under Agreement', property.Status__c);
        Assert.areEqual(Date.today(), property.Date_Agreement__c);
    }

    @isTest
    static void acceptRefusedWhenPropertyAlreadyUnderAgreement() {
        Id propertyId = OfferTestFactory.property().Id;
        Offer__c jane;
        System.runAs(OfferTestFactory.agent()) {
            jane = OfferService.submit(propertyId, 'Jane Buyer', 820000);
        }
        setPropertyStatus('Under Agreement');
        System.runAs(OfferTestFactory.agent()) {
            try {
                OfferService.accept(jane.Id);
                Assert.fail('Property is already under agreement');
            } catch (OfferService.OfferException e) {
                Assert.isTrue(e.getMessage().contains('not taking offers'));
            }
        }
        Assert.areEqual(
            OfferService.STATUS_SUBMITTED,
            OfferTestFactory.offer(jane.Id).Status__c
        );
    }

    @isTest
    static void rejectOnlyAppliesToOpenOffers() {
        Id propertyId = OfferTestFactory.property().Id;
        System.runAs(OfferTestFactory.agent()) {
            Offer__c jane = OfferService.submit(
                propertyId,
                'Jane Buyer',
                820000
            );
            OfferService.reject(jane.Id);
            Assert.areEqual(
                OfferService.STATUS_REJECTED,
                OfferTestFactory.offer(jane.Id).Status__c
            );
            try {
                OfferService.reject(jane.Id);
                Assert.fail('Rejected offers are closed');
            } catch (OfferService.OfferException e) {
                Assert.areEqual(
                    'Only open offers can be rejected.',
                    e.getMessage()
                );
            }
            try {
                OfferService.accept(jane.Id);
                Assert.fail('Rejected offers cannot be accepted');
            } catch (OfferService.OfferException e) {
                Assert.areEqual(
                    'Only submitted or approved offers can be accepted.',
                    e.getMessage()
                );
            }
        }
    }

    @isTest
    static void missingOfferIsReported() {
        Id propertyId = OfferTestFactory.property().Id;
        Offer__c jane;
        System.runAs(OfferTestFactory.agent()) {
            jane = OfferService.submit(propertyId, 'Jane Buyer', 820000);
        }
        delete jane;
        System.runAs(OfferTestFactory.agent()) {
            try {
                OfferService.reject(jane.Id);
                Assert.fail('Offer was deleted');
            } catch (OfferService.OfferException e) {
                Assert.areEqual('Offer not found.', e.getMessage());
            }
        }
    }

    @isTest
    static void triggerBlocksDirectWrites() {
        Id propertyId = OfferTestFactory.property().Id;
        System.runAs(OfferTestFactory.broker()) {
            Database.SaveResult direct = Database.insert(
                new Offer__c(
                    Property__c = propertyId,
                    Buyer_Name__c = 'Sneaky',
                    Amount__c = 500000,
                    Status__c = OfferService.STATUS_APPROVED
                ),
                false
            );
            Assert.isFalse(direct.isSuccess());
            Assert.isTrue(
                direct.getErrors()[0].getMessage().contains('Offers card')
            );

            Offer__c sam = OfferService.submit(
                propertyId,
                'Sam Lowball',
                720000
            );
            Database.SaveResult statusChange = Database.update(
                new Offer__c(
                    Id = sam.Id,
                    Status__c = OfferService.STATUS_ACCEPTED
                ),
                false
            );
            Assert.isFalse(statusChange.isSuccess());
            Assert.isTrue(
                statusChange.getErrors()[0]
                    .getMessage()
                    .contains('Approve, Accept or Reject')
            );

            Database.SaveResult amountChange = Database.update(
                new Offer__c(Id = sam.Id, Amount__c = 840000),
                false
            );
            Assert.isFalse(amountChange.isSuccess());
            Assert.isTrue(
                amountChange.getErrors()[0]
                    .getMessage()
                    .contains('cannot be changed')
            );

            Database.SaveResult nameChange = Database.update(
                new Offer__c(Id = sam.Id, Buyer_Name__c = 'Samuel Lowball'),
                false
            );
            Assert.isTrue(nameChange.isSuccess());
        }
    }
}
