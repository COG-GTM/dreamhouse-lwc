@IsTest
private class OfferServiceTest {
    private static final Decimal ASKING = 845000;

    @TestSetup
    static void setup() {
        OfferTestFactory.createUsers();
        OfferTestFactory.createProperty('Offer Test Home', ASKING, 'Available');
    }

    private static Property__c property() {
        return [
            SELECT Id, Status__c, Date_Agreement__c, Price__c
            FROM Property__c
            WHERE Name = 'Offer Test Home'
        ];
    }

    private static Offer__c reload(Id offerId) {
        return [
            SELECT
                Status__c,
                Amount__c,
                Percent_Below_Asking__c,
                Approved_Percent_Below__c
            FROM Offer__c
            WHERE Id = :offerId
        ];
    }

    @IsTest
    static void percentBelowAskingRoundsHalfUpToOneDecimal() {
        Assert.areEqual(14.8, OfferService.percentBelowAsking(ASKING, 720000));
        Assert.areEqual(3.0, OfferService.percentBelowAsking(ASKING, 820000));
        Assert.areEqual(10.1, OfferService.percentBelowAsking(100000, 89950));
        Assert.areEqual(10.0, OfferService.percentBelowAsking(100000, 89951));
        Assert.areEqual(-5.0, OfferService.percentBelowAsking(100000, 105000));
        Assert.isTrue(OfferService.needsApproval(10.1));
        Assert.isFalse(OfferService.needsApproval(10.0));
    }

    @IsTest
    static void percentBelowAskingRequiresAskingPrice() {
        try {
            OfferService.percentBelowAsking(null, 100);
            Assert.fail('Expected an exception');
        } catch (OfferService.OfferException e) {
            Assert.isTrue(e.getMessage().contains('no asking price'));
        }
    }

    @IsTest
    static void submitWithinThresholdIsSubmitted() {
        Offer__c offer;
        System.runAs(OfferTestFactory.agent()) {
            Test.startTest();
            offer = OfferService.submitOffer(
                property().Id,
                '  Jane Buyer ',
                820000
            );
            Test.stopTest();
        }
        Offer__c saved = reload(offer.Id);
        Assert.areEqual(OfferService.STATUS_SUBMITTED, saved.Status__c);
        Assert.areEqual(3.0, saved.Percent_Below_Asking__c);
        Assert.areEqual('Jane Buyer', offer.Buyer_Name__c);
    }

    @IsTest
    static void submitMoreThanTenPercentBelowNeedsApproval() {
        Offer__c offer;
        System.runAs(OfferTestFactory.agent()) {
            offer = OfferService.submitOffer(
                property().Id,
                'Sam Lowball',
                720000
            );
        }
        Offer__c saved = reload(offer.Id);
        Assert.areEqual(OfferService.STATUS_NEEDS_APPROVAL, saved.Status__c);
        Assert.areEqual(14.8, saved.Percent_Below_Asking__c);
    }

    @IsTest
    static void submitRejectsInvalidInput() {
        Id propertyId = property().Id;
        for (Decimal amount : new List<Decimal>{ null, 0, -1 }) {
            try {
                OfferService.submitOffer(propertyId, 'Buyer', amount);
                Assert.fail('Expected an exception for ' + amount);
            } catch (OfferService.OfferException e) {
                Assert.isTrue(e.getMessage().contains('greater than zero'));
            }
        }
        try {
            OfferService.submitOffer(propertyId, ' ', 800000);
            Assert.fail('Expected an exception');
        } catch (OfferService.OfferException e) {
            Assert.isTrue(e.getMessage().contains('buyer name'));
        }
        Assert.areEqual(0, [SELECT COUNT() FROM Offer__c]);
    }

    @IsTest
    static void submitBlockedOnClosedProperties() {
        for (
            String status : new List<String>{
                'Closed',
                'Under Agreement',
                'Contracted'
            }
        ) {
            Property__c closed = OfferTestFactory.createProperty(
                'Closed ' + status,
                500000,
                status
            );
            try {
                OfferService.submitOffer(closed.Id, 'Buyer', 490000);
                Assert.fail('Expected an exception for ' + status);
            } catch (OfferService.OfferException e) {
                Assert.isTrue(e.getMessage().contains(status));
            }
        }
    }

    @IsTest
    static void submitRequiresExistingPropertyWithPrice() {
        Property__c noPrice = OfferTestFactory.createProperty(
            'No Price',
            null,
            'Available'
        );
        try {
            OfferService.submitOffer(noPrice.Id, 'Buyer', 1000);
            Assert.fail('Expected an exception');
        } catch (OfferService.OfferException e) {
            Assert.isTrue(e.getMessage().contains('no asking price'));
        }
        delete noPrice;
        try {
            OfferService.submitOffer(noPrice.Id, 'Buyer', 1000);
            Assert.fail('Expected an exception');
        } catch (OfferService.OfferException e) {
            Assert.isTrue(e.getMessage().contains('not found'));
        }
    }

    @IsTest
    static void agentCannotApproveButBrokerCan() {
        Offer__c offer;
        System.runAs(OfferTestFactory.agent()) {
            offer = OfferService.submitOffer(
                property().Id,
                'Sam Lowball',
                720000
            );
            Assert.isFalse(OfferService.canApprove());
            try {
                OfferService.approveOffer(offer.Id);
                Assert.fail('Agent should not be able to approve');
            } catch (OfferService.OfferException e) {
                Assert.isTrue(e.getMessage().contains('Approve Offers'));
            }
        }
        Assert.areEqual(
            OfferService.STATUS_NEEDS_APPROVAL,
            reload(offer.Id).Status__c
        );
        System.runAs(OfferTestFactory.broker()) {
            Assert.isTrue(OfferService.canApprove());
            OfferService.approveOffer(offer.Id);
        }
        Assert.areEqual(
            OfferService.STATUS_APPROVED,
            reload(offer.Id).Status__c
        );
    }

    @IsTest
    static void approveOnlyAppliesToNeedsApproval() {
        System.runAs(OfferTestFactory.broker()) {
            Offer__c offer = OfferService.submitOffer(
                property().Id,
                'Jane Buyer',
                820000
            );
            try {
                OfferService.approveOffer(offer.Id);
                Assert.fail('Expected an exception');
            } catch (OfferService.OfferException e) {
                Assert.isTrue(e.getMessage().contains('need approval'));
            }
        }
    }

    @IsTest
    static void needsApprovalOfferCannotBeAcceptedUntilApproved() {
        System.runAs(OfferTestFactory.broker()) {
            Offer__c offer = OfferService.submitOffer(
                property().Id,
                'Sam Lowball',
                720000
            );
            try {
                OfferService.acceptOffer(offer.Id);
                Assert.fail('Expected an exception');
            } catch (OfferService.OfferException e) {
                Assert.isTrue(e.getMessage().contains('needs broker approval'));
            }
            OfferService.approveOffer(offer.Id);
            OfferService.acceptOffer(offer.Id);
        }
    }

    @IsTest
    static void acceptRejectsOtherOffersAndPutsPropertyUnderAgreement() {
        Offer__c jane;
        Offer__c sam;
        Offer__c other;
        System.runAs(OfferTestFactory.broker()) {
            Id propertyId = property().Id;
            jane = OfferService.submitOffer(propertyId, 'Jane Buyer', 820000);
            other = OfferService.submitOffer(
                propertyId,
                'Other Lowball',
                700000
            );
            sam = OfferService.submitOffer(propertyId, 'Sam Lowball', 720000);
            OfferService.approveOffer(sam.Id);
            Test.startTest();
            Offer__c accepted = OfferService.acceptOffer(sam.Id);
            Test.stopTest();
            Assert.areEqual(OfferService.STATUS_ACCEPTED, accepted.Status__c);
        }
        Assert.areEqual(OfferService.STATUS_ACCEPTED, reload(sam.Id).Status__c);
        Assert.areEqual(
            OfferService.STATUS_REJECTED,
            reload(jane.Id).Status__c
        );
        Assert.areEqual(
            OfferService.STATUS_REJECTED,
            reload(other.Id).Status__c
        );
        Property__c saved = property();
        Assert.areEqual('Under Agreement', saved.Status__c);
        Assert.areEqual(Date.today(), saved.Date_Agreement__c);
    }

    @IsTest
    static void acceptRefusedWhenPropertyAlreadyUnderAgreement() {
        Offer__c jane;
        Offer__c bob;
        System.runAs(OfferTestFactory.agent()) {
            Id propertyId = property().Id;
            jane = OfferService.submitOffer(propertyId, 'Jane Buyer', 820000);
            bob = OfferService.submitOffer(propertyId, 'Bob Buyer', 830000);
        }
        update new Property__c(
            Id = property().Id,
            Status__c = 'Under Agreement'
        );
        System.runAs(OfferTestFactory.agent()) {
            try {
                OfferService.acceptOffer(bob.Id);
                Assert.fail('Expected an exception');
            } catch (OfferService.OfferException e) {
                Assert.isTrue(
                    e.getMessage().contains('no longer taking offers')
                );
            }
        }
        Assert.areEqual(
            OfferService.STATUS_SUBMITTED,
            reload(bob.Id).Status__c
        );
    }

    @IsTest
    static void acceptRechecksDiscountAgainstCurrentAskingPrice() {
        Offer__c jane;
        System.runAs(OfferTestFactory.agent()) {
            jane = OfferService.submitOffer(
                property().Id,
                'Jane Buyer',
                820000
            );
        }
        update new Property__c(Id = property().Id, Price__c = 950000);
        System.runAs(OfferTestFactory.agent()) {
            try {
                OfferService.acceptOffer(jane.Id);
                Assert.fail('Expected an exception');
            } catch (OfferService.OfferException e) {
                Assert.isTrue(e.getMessage().contains('13.7% below asking'));
            }
        }
        Assert.areEqual(
            OfferService.STATUS_SUBMITTED,
            reload(jane.Id).Status__c
        );
    }

    @IsTest
    static void rejectClosesOpenOffersOnly() {
        System.runAs(OfferTestFactory.agent()) {
            Offer__c offer = OfferService.submitOffer(
                property().Id,
                'Jane Buyer',
                820000
            );
            Assert.areEqual(
                OfferService.STATUS_REJECTED,
                OfferService.rejectOffer(offer.Id).Status__c
            );
            try {
                OfferService.rejectOffer(offer.Id);
                Assert.fail('Expected an exception');
            } catch (OfferService.OfferException e) {
                Assert.isTrue(e.getMessage().contains('already closed'));
            }
            try {
                OfferService.acceptOffer(offer.Id);
                Assert.fail('Expected an exception');
            } catch (OfferService.OfferException e) {
                Assert.isTrue(e.getMessage().contains('already closed'));
            }
        }
    }

    @IsTest
    static void unknownOfferIsReported() {
        Offer__c offer = OfferService.submitOffer(
            property().Id,
            'Jane Buyer',
            820000
        );
        Id offerId = offer.Id;
        delete new Offer__c(Id = offerId);
        try {
            OfferService.rejectOffer(offerId);
            Assert.fail('Expected an exception');
        } catch (OfferService.OfferException e) {
            Assert.isTrue(e.getMessage().contains('Offer not found'));
        }
    }

    @IsTest
    static void submittedOfferPushedOverThresholdCanBeApproved() {
        Offer__c jane;
        System.runAs(OfferTestFactory.agent()) {
            jane = OfferService.submitOffer(
                property().Id,
                'Jane Buyer',
                820000
            );
        }
        update new Property__c(Id = property().Id, Price__c = 950000);
        System.runAs(OfferTestFactory.broker()) {
            OfferService.approveOffer(jane.Id);
            Assert.areEqual(13.7, reload(jane.Id).Approved_Percent_Below__c);
            OfferService.acceptOffer(jane.Id);
        }
        Assert.areEqual(
            OfferService.STATUS_ACCEPTED,
            reload(jane.Id).Status__c
        );
    }

    @IsTest
    static void approvedOfferNeedsReapprovalWhenPriceRises() {
        Offer__c sam;
        System.runAs(OfferTestFactory.broker()) {
            sam = OfferService.submitOffer(
                property().Id,
                'Sam Lowball',
                720000
            );
            OfferService.approveOffer(sam.Id);
        }
        Assert.areEqual(14.8, reload(sam.Id).Approved_Percent_Below__c);
        update new Property__c(Id = property().Id, Price__c = 900000);
        System.runAs(OfferTestFactory.broker()) {
            try {
                OfferService.acceptOffer(sam.Id);
                Assert.fail('Expected an exception');
            } catch (OfferService.OfferException e) {
                Assert.isTrue(e.getMessage().contains('20.0% below asking'));
            }
            OfferService.approveOffer(sam.Id);
            Assert.areEqual(20.0, reload(sam.Id).Approved_Percent_Below__c);
            OfferService.acceptOffer(sam.Id);
        }
        Assert.areEqual(OfferService.STATUS_ACCEPTED, reload(sam.Id).Status__c);
    }

    @IsTest
    static void approvedOfferStillAcceptableWhenPriceDrops() {
        Offer__c sam;
        System.runAs(OfferTestFactory.broker()) {
            sam = OfferService.submitOffer(
                property().Id,
                'Sam Lowball',
                720000
            );
            OfferService.approveOffer(sam.Id);
        }
        update new Property__c(Id = property().Id, Price__c = 820000);
        System.runAs(OfferTestFactory.agent()) {
            OfferService.acceptOffer(sam.Id);
        }
        Assert.areEqual(OfferService.STATUS_ACCEPTED, reload(sam.Id).Status__c);
    }

    @IsTest
    static void acceptRefusedWhenPropertyAlreadyHasAcceptedOffer() {
        Offer__c jane;
        Offer__c bob;
        System.runAs(OfferTestFactory.agent()) {
            jane = OfferService.submitOffer(
                property().Id,
                'Jane Buyer',
                820000
            );
            OfferService.acceptOffer(jane.Id);
        }
        update new Property__c(Id = property().Id, Status__c = 'Available');
        System.runAs(OfferTestFactory.agent()) {
            bob = OfferService.submitOffer(property().Id, 'Bob Buyer', 830000);
            try {
                OfferService.acceptOffer(bob.Id);
                Assert.fail('Expected an exception');
            } catch (OfferService.OfferException e) {
                Assert.isTrue(
                    e.getMessage().contains('already has an accepted offer')
                );
            }
        }
        Assert.areEqual(
            OfferService.STATUS_SUBMITTED,
            reload(bob.Id).Status__c
        );
    }

    @IsTest
    static void triggerOnlyAllowsTheExactServiceWrite() {
        Id propertyId = property().Id;
        Offer__c sam = OfferService.submitOffer(
            propertyId,
            'Sam Lowball',
            720000
        );
        Offer__c jane = OfferService.submitOffer(
            propertyId,
            'Jane Buyer',
            820000
        );
        Offer__c old = sam.clone(true);

        // Authorization for a different offer doesn't cover this one.
        OfferService.authorizedUpdates.put(
            jane.Id,
            new Offer__c(Id = jane.Id, Status__c = OfferService.STATUS_REJECTED)
        );
        Offer__c approve = new Offer__c(
            Id = sam.Id,
            Amount__c = sam.Amount__c,
            Percent_Below_Asking__c = sam.Percent_Below_Asking__c,
            Status__c = OfferService.STATUS_APPROVED
        );
        OfferService.validateBeforeUpdate(
            new List<Offer__c>{ approve },
            new Map<Id, Offer__c>{ sam.Id => old }
        );
        Assert.isTrue(approve.hasErrors());

        // A matching status with a different approval level is refused too.
        OfferService.authorizedUpdates.put(
            sam.Id,
            new Offer__c(
                Id = sam.Id,
                Status__c = OfferService.STATUS_APPROVED,
                Approved_Percent_Below__c = 14.8
            )
        );
        Offer__c widened = approve.clone(true);
        widened.Approved_Percent_Below__c = 90;
        OfferService.validateBeforeUpdate(
            new List<Offer__c>{ widened },
            new Map<Id, Offer__c>{ sam.Id => old }
        );
        Assert.isTrue(widened.hasErrors());

        // An insert that doesn't match the pending service insert is refused.
        OfferService.authorizedInserts.add(
            new Offer__c(
                Property__c = propertyId,
                Buyer_Name__c = 'Real',
                Amount__c = 800000,
                Percent_Below_Asking__c = 5.3,
                Status__c = OfferService.STATUS_SUBMITTED
            )
        );
        Offer__c sneaky = new Offer__c(
            Property__c = propertyId,
            Buyer_Name__c = 'Real',
            Amount__c = 800000,
            Percent_Below_Asking__c = 5.3,
            Status__c = OfferService.STATUS_APPROVED
        );
        OfferService.validateBeforeInsert(new List<Offer__c>{ sneaky });
        Assert.isTrue(sneaky.hasErrors());
    }

    @IsTest
    static void triggerBlocksDirectStatusAndAmountEdits() {
        Offer__c offer = OfferService.submitOffer(
            property().Id,
            'Sam Lowball',
            720000
        );
        Map<String, Object> edits = new Map<String, Object>{
            'Status__c' => OfferService.STATUS_APPROVED,
            'Amount__c' => 830000,
            'Percent_Below_Asking__c' => 0,
            'Approved_Percent_Below__c' => 50
        };
        for (String field : edits.keySet()) {
            Offer__c change = new Offer__c(Id = offer.Id);
            change.put(field, edits.get(field));
            Database.SaveResult result = Database.update(change, false);
            Assert.isFalse(result.isSuccess(), field + ' edit should fail');
        }
        Offer__c saved = reload(offer.Id);
        Assert.areEqual(OfferService.STATUS_NEEDS_APPROVAL, saved.Status__c);
        Assert.areEqual(720000, saved.Amount__c);
    }

    @IsTest
    static void triggerBlocksDirectInsert() {
        Database.SaveResult result = Database.insert(
            new Offer__c(
                Property__c = property().Id,
                Buyer_Name__c = 'Direct',
                Amount__c = 100,
                Status__c = OfferService.STATUS_APPROVED
            ),
            false
        );
        Assert.isFalse(result.isSuccess());
        Assert.isTrue(
            result.getErrors()[0].getMessage().contains('Offers card')
        );
    }

    @IsTest
    static void triggerEnforcesStatusTransitions() {
        Offer__c offer = OfferService.submitOffer(
            property().Id,
            'Jane Buyer',
            820000
        );
        Map<Id, Offer__c> oldOffers = new Map<Id, Offer__c>{
            offer.Id => offer.clone(true)
        };
        Property__c other = OfferTestFactory.createProperty(
            'Other Home',
            100,
            'Available'
        );
        // Master-detail fields aren't writeable on an existing record in Apex,
        // so build the "new" version through JSON like the trigger would see it.
        List<Offer__c> newOffers = new List<Offer__c>{
            (Offer__c) JSON.deserialize(
                JSON.serialize(
                    new Map<String, Object>{
                        'Id' => offer.Id,
                        'Property__c' => other.Id,
                        'Amount__c' => 1,
                        'Percent_Below_Asking__c' => offer.Percent_Below_Asking__c,
                        'Status__c' => OfferService.STATUS_APPROVED
                    }
                ),
                Offer__c.class
            )
        };
        OfferService.validateBeforeUpdate(newOffers, oldOffers);
        Assert.isTrue(newOffers[0].hasErrors());
        Assert.areEqual(3, newOffers[0].getErrors().size());
    }

    @IsTest
    static void triggerRejectsDisallowedTransitionsEvenFromService() {
        Offer__c accepted = new Offer__c(
            Id = OfferService.submitOffer(property().Id, 'Jane', 820000).Id,
            Status__c = OfferService.STATUS_SUBMITTED
        );
        Offer__c old = accepted.clone(true);
        old.Status__c = OfferService.STATUS_ACCEPTED;
        OfferService.authorizedUpdates.put(accepted.Id, accepted.clone(true));
        OfferService.validateBeforeUpdate(
            new List<Offer__c>{ accepted },
            new Map<Id, Offer__c>{ old.Id => old }
        );
        Assert.isTrue(
            accepted.getErrors()[0].getMessage().contains('cannot move from')
        );
    }
}
