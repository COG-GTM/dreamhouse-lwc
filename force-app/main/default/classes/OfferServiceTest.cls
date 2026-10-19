@IsTest
private class OfferServiceTest {
    private static final Decimal ASKING = 845000;

    @TestSetup
    static void setup() {
        System.runAs(new User(Id = UserInfo.getUserId())) {
            User agent = OfferTestFactory.createUser('agent', false);
            User broker = OfferTestFactory.createUser('broker', true);
        }
        insert new List<Property__c>{
            new Property__c(
                Name = 'Open House',
                Price__c = ASKING,
                Status__c = 'Available'
            ),
            new Property__c(
                Name = 'Round Numbers',
                Price__c = 1000000,
                Status__c = 'Available'
            ),
            new Property__c(
                Name = 'Already Sold',
                Price__c = ASKING,
                Status__c = 'Closed'
            ),
            new Property__c(
                Name = 'In Escrow',
                Price__c = ASKING,
                Status__c = 'Under Agreement'
            ),
            new Property__c(
                Name = 'Contracted House',
                Price__c = ASKING,
                Status__c = 'Contracted'
            )
        };
    }

    private static Id propertyId(String name) {
        return [SELECT Id FROM Property__c WHERE Name = :name].Id;
    }

    private static Offer__c reload(Id offerId) {
        return [
            SELECT Id, Amount__c, Percent_Below_Asking__c, Status__c
            FROM Offer__c
            WHERE Id = :offerId
        ];
    }

    private static String submitError(Id propId, String buyer, Decimal amount) {
        try {
            OfferService.submitOffer(propId, buyer, amount);
        } catch (OfferService.OfferException e) {
            return e.getMessage();
        }
        return null;
    }

    @IsTest
    static void percentBelowAskingRoundsHalfUpToOneDecimal() {
        Assert.areEqual(14.8, OfferService.percentBelowAsking(ASKING, 720000));
        Assert.areEqual(3.0, OfferService.percentBelowAsking(ASKING, 820000));
        Assert.areEqual(10.1, OfferService.percentBelowAsking(1000000, 899500));
        Assert.areEqual(
            -5.0,
            OfferService.percentBelowAsking(1000000, 1050000)
        );
        Assert.isNull(OfferService.percentBelowAsking(null, 100));
        Assert.isNull(OfferService.percentBelowAsking(0, 100));
        Assert.isNull(OfferService.percentBelowAsking(100, null));
    }

    @IsTest
    static void submitWithinTenPercentIsSubmitted() {
        Offer__c offer;
        System.runAs(OfferTestFactory.getUser('agent')) {
            Test.startTest();
            offer = OfferService.submitOffer(
                propertyId('Open House'),
                '  Jane Buyer ',
                820000
            );
            Test.stopTest();
        }
        Offer__c saved = [
            SELECT Buyer_Name__c, Percent_Below_Asking__c, Status__c
            FROM Offer__c
            WHERE Id = :offer.Id
        ];
        Assert.areEqual('Jane Buyer', saved.Buyer_Name__c);
        Assert.areEqual(3.0, saved.Percent_Below_Asking__c);
        Assert.areEqual(OfferService.STATUS_SUBMITTED, saved.Status__c);
    }

    @IsTest
    static void submitMoreThanTenPercentBelowNeedsApproval() {
        Offer__c offer;
        System.runAs(OfferTestFactory.getUser('agent')) {
            offer = OfferService.submitOffer(
                propertyId('Open House'),
                'Sam Lowball',
                720000
            );
        }
        Offer__c saved = reload(offer.Id);
        Assert.areEqual(14.8, saved.Percent_Below_Asking__c);
        Assert.areEqual(OfferService.STATUS_NEEDS_APPROVAL, saved.Status__c);
    }

    @IsTest
    static void thresholdUsesRoundedPercent() {
        Id propId = propertyId('Round Numbers');
        Offer__c exactlyTen;
        Offer__c roundsDownToTen;
        Offer__c roundsUpPastTen;
        System.runAs(OfferTestFactory.getUser('agent')) {
            exactlyTen = OfferService.submitOffer(propId, 'A', 900000);
            roundsDownToTen = OfferService.submitOffer(propId, 'B', 899600);
            roundsUpPastTen = OfferService.submitOffer(propId, 'C', 899500);
        }
        Assert.areEqual(
            OfferService.STATUS_SUBMITTED,
            reload(exactlyTen.Id).Status__c
        );
        Assert.areEqual(
            OfferService.STATUS_SUBMITTED,
            reload(roundsDownToTen.Id).Status__c
        );
        Assert.areEqual(
            OfferService.STATUS_NEEDS_APPROVAL,
            reload(roundsUpPastTen.Id).Status__c
        );
    }

    @IsTest
    static void submitRejectsBadInput() {
        Id propId = propertyId('Open House');
        System.runAs(OfferTestFactory.getUser('agent')) {
            Assert.areEqual(
                'Offer amount must be greater than zero.',
                submitError(propId, 'Zero', 0)
            );
            Assert.areEqual(
                'Offer amount must be greater than zero.',
                submitError(propId, 'Negative', -1)
            );
            Assert.areEqual(
                'Offer amount must be greater than zero.',
                submitError(propId, 'Null', null)
            );
            Assert.areEqual(
                'Enter the buyer name.',
                submitError(propId, ' ', 500000)
            );
        }
        Assert.areEqual(0, [SELECT COUNT() FROM Offer__c]);
    }

    @IsTest
    static void submitBlockedOnClosedUnderAgreementOrContractedProperty() {
        System.runAs(OfferTestFactory.getUser('agent')) {
            for (
                String name : new List<String>{
                    'Already Sold',
                    'In Escrow',
                    'Contracted House'
                }
            ) {
                String error = submitError(propertyId(name), 'Buyer', 800000);
                Assert.isNotNull(error, name + ' should not take offers');
                Assert.isTrue(error.contains('no longer taking offers'), error);
            }
        }
        Assert.areEqual(0, [SELECT COUNT() FROM Offer__c]);
    }

    @IsTest
    static void agentCannotApproveButBrokerCan() {
        Offer__c offer;
        System.runAs(OfferTestFactory.getUser('agent')) {
            offer = OfferService.submitOffer(
                propertyId('Open House'),
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

        System.runAs(OfferTestFactory.getUser('broker')) {
            Assert.isTrue(OfferService.canApprove());
            OfferService.approveOffer(offer.Id);
        }
        Assert.areEqual(
            OfferService.STATUS_APPROVED,
            reload(offer.Id).Status__c
        );
    }

    @IsTest
    static void approveOnlyAppliesToOffersNeedingApproval() {
        System.runAs(OfferTestFactory.getUser('broker')) {
            Offer__c offer = OfferService.submitOffer(
                propertyId('Open House'),
                'Jane Buyer',
                820000
            );
            try {
                OfferService.approveOffer(offer.Id);
                Assert.fail('Submitted offers do not need approval');
            } catch (OfferService.OfferException e) {
                Assert.areEqual(
                    'Only offers that need approval can be approved.',
                    e.getMessage()
                );
            }
        }
    }

    @IsTest
    static void needsApprovalOfferCannotBeAcceptedUntilApproved() {
        Id propId = propertyId('Open House');
        System.runAs(OfferTestFactory.getUser('broker')) {
            Offer__c jane = OfferService.submitOffer(
                propId,
                'Jane Buyer',
                820000
            );
            Offer__c sam = OfferService.submitOffer(
                propId,
                'Sam Lowball',
                720000
            );
            try {
                OfferService.acceptOffer(sam.Id);
                Assert.fail('Needs Approval offers cannot be accepted');
            } catch (OfferService.OfferException e) {
                Assert.isTrue(e.getMessage().contains('needs broker approval'));
            }

            Test.startTest();
            OfferService.approveOffer(sam.Id);
            OfferService.acceptOffer(sam.Id);
            Test.stopTest();

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
            WHERE Id = :propId
        ];
        Assert.areEqual('Under Agreement', property.Status__c);
        Assert.areEqual(Date.today(), property.Date_Agreement__c);
    }

    @IsTest
    static void acceptSubmittedOfferRejectsOthersButLeavesClosedOffers() {
        Id propId = propertyId('Open House');
        System.runAs(OfferTestFactory.getUser('agent')) {
            Offer__c first = OfferService.submitOffer(propId, 'First', 800000);
            Offer__c second = OfferService.submitOffer(
                propId,
                'Second',
                830000
            );
            Offer__c lowball = OfferService.submitOffer(
                propId,
                'Lowball',
                600000
            );
            OfferService.rejectOffer(first.Id);
            OfferService.acceptOffer(second.Id);

            Assert.areEqual(
                OfferService.STATUS_REJECTED,
                reload(first.Id).Status__c
            );
            Assert.areEqual(
                OfferService.STATUS_ACCEPTED,
                reload(second.Id).Status__c
            );
            Assert.areEqual(
                OfferService.STATUS_REJECTED,
                reload(lowball.Id).Status__c
            );

            Assert.areEqual(3, OfferService.getOffers(propId).size());
        }
    }

    @IsTest
    static void cannotAcceptOnceThePropertyIsUnderAgreement() {
        Id propId = propertyId('Open House');
        System.runAs(OfferTestFactory.getUser('broker')) {
            Offer__c first = OfferService.submitOffer(propId, 'First', 840000);
            Offer__c second = OfferService.submitOffer(
                propId,
                'Second',
                830000
            );
            OfferService.acceptOffer(first.Id);
            try {
                OfferService.acceptOffer(second.Id);
                Assert.fail('Property is already under agreement');
            } catch (OfferService.OfferException e) {
                Assert.isTrue(e.getMessage().contains('Under Agreement'));
            }
            try {
                OfferService.submitOffer(propId, 'Late', 845000);
                Assert.fail('Property is already under agreement');
            } catch (OfferService.OfferException e) {
                Assert.isTrue(
                    e.getMessage().contains('no longer taking offers')
                );
            }
        }
    }

    @IsTest
    static void rejectOnlyAppliesToOpenOffers() {
        System.runAs(OfferTestFactory.getUser('agent')) {
            Offer__c offer = OfferService.submitOffer(
                propertyId('Open House'),
                'Jane Buyer',
                820000
            );
            OfferService.rejectOffer(offer.Id);
            try {
                OfferService.rejectOffer(offer.Id);
                Assert.fail('Already rejected');
            } catch (OfferService.OfferException e) {
                Assert.areEqual(
                    'Only open offers can be rejected.',
                    e.getMessage()
                );
            }
            try {
                OfferService.acceptOffer(offer.Id);
                Assert.fail('Rejected offers cannot be accepted');
            } catch (OfferService.OfferException e) {
                Assert.areEqual(
                    'Only submitted or approved offers can be accepted.',
                    e.getMessage()
                );
            }
        }
    }

    @IsTest
    static void unknownOfferIsReported() {
        Id propId = propertyId('Open House');
        Offer__c offer = OfferService.submitOffer(propId, 'Gone', 820000);
        Id offerId = offer.Id;
        delete offer;
        try {
            OfferService.rejectOffer(offerId);
            Assert.fail('Offer was deleted');
        } catch (OfferService.OfferException e) {
            Assert.areEqual('Offer not found.', e.getMessage());
        }
    }

    @IsTest
    static void directStatusEditsAreBlocked() {
        Offer__c offer = OfferService.submitOffer(
            propertyId('Open House'),
            'Sam Lowball',
            720000
        );
        Database.SaveResult result = Database.update(
            new Offer__c(
                Id = offer.Id,
                Status__c = OfferService.STATUS_ACCEPTED
            ),
            false
        );
        Assert.isFalse(result.isSuccess());
        Assert.isTrue(
            result.getErrors()[0]
                .getMessage()
                .contains('Use Approve, Accept or Reject')
        );
        Assert.areEqual(
            OfferService.STATUS_NEEDS_APPROVAL,
            reload(offer.Id).Status__c
        );
    }

    @IsTest
    static void amountAndPercentAreImmutable() {
        Offer__c offer = OfferService.submitOffer(
            propertyId('Open House'),
            'Sam Lowball',
            720000
        );
        Database.SaveResult amountResult = Database.update(
            new Offer__c(Id = offer.Id, Amount__c = 840000),
            false
        );
        Assert.isFalse(amountResult.isSuccess());
        Database.SaveResult percentResult = Database.update(
            new Offer__c(Id = offer.Id, Percent_Below_Asking__c = 1),
            false
        );
        Assert.isFalse(percentResult.isSuccess());
        Offer__c saved = reload(offer.Id);
        Assert.areEqual(720000, saved.Amount__c);
        Assert.areEqual(14.8, saved.Percent_Below_Asking__c);
    }

    @IsTest
    static void insertsOutsideTheServiceAreRecalculated() {
        Id propId = propertyId('Open House');
        Offer__c sneaky = new Offer__c(
            Property__c = propId,
            Buyer_Name__c = 'Sneaky',
            Amount__c = 600000,
            Percent_Below_Asking__c = 0,
            Status__c = OfferService.STATUS_APPROVED
        );
        insert sneaky;
        Offer__c saved = reload(sneaky.Id);
        Assert.areEqual(29.0, saved.Percent_Below_Asking__c);
        Assert.areEqual(OfferService.STATUS_NEEDS_APPROVAL, saved.Status__c);

        List<Database.SaveResult> results = Database.insert(
            new List<Offer__c>{
                new Offer__c(
                    Property__c = propId,
                    Buyer_Name__c = 'Zero',
                    Amount__c = 0
                ),
                new Offer__c(
                    Property__c = propertyId('Already Sold'),
                    Buyer_Name__c = 'Late',
                    Amount__c = 800000
                )
            },
            false
        );
        Assert.isFalse(results[0].isSuccess());
        Assert.isFalse(results[1].isSuccess());
    }
}
