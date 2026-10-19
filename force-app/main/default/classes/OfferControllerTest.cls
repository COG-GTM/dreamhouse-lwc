@IsTest
private class OfferControllerTest {
    @TestSetup
    static void setup() {
        System.runAs(new User(Id = UserInfo.getUserId())) {
            OfferTestFactory.createUser('agent', false);
            OfferTestFactory.createUser('broker', true);
        }
        insert new Property__c(
            Name = 'Contemporary Luxury',
            Price__c = 845000,
            Status__c = 'Available'
        );
    }

    private static Id propertyId() {
        return [SELECT Id FROM Property__c LIMIT 1].Id;
    }

    @IsTest
    static void brokerRunsTheFullDiscountApprovalFlow() {
        Id propId = propertyId();
        System.runAs(OfferTestFactory.getUser('broker')) {
            OfferController.OfferContext empty = OfferController.getOfferContext(
                propId
            );
            Assert.areEqual(0, empty.offers.size());
            Assert.isTrue(empty.canApprove);

            Offer__c jane = OfferController.submitOffer(
                propId,
                'Jane Buyer',
                820000
            );
            Offer__c sam = OfferController.submitOffer(
                propId,
                'Sam Lowball',
                720000
            );
            Assert.areEqual(OfferService.STATUS_SUBMITTED, jane.Status__c);
            Assert.areEqual(OfferService.STATUS_NEEDS_APPROVAL, sam.Status__c);

            Test.startTest();
            OfferController.approveOffer(sam.Id);
            OfferController.acceptOffer(sam.Id);
            Test.stopTest();

            Map<String, String> statusByBuyer = new Map<String, String>();
            for (
                Offer__c offer : OfferController.getOfferContext(propId).offers
            ) {
                statusByBuyer.put(offer.Buyer_Name__c, offer.Status__c);
            }
            Assert.areEqual(
                OfferService.STATUS_ACCEPTED,
                statusByBuyer.get('Sam Lowball')
            );
            Assert.areEqual(
                OfferService.STATUS_REJECTED,
                statusByBuyer.get('Jane Buyer')
            );
        }
        Assert.areEqual(
            'Under Agreement',
            [SELECT Status__c FROM Property__c WHERE Id = :propId].Status__c
        );
    }

    @IsTest
    static void agentSeesNoApproveRightsAndGetsAFriendlyError() {
        Id propId = propertyId();
        System.runAs(OfferTestFactory.getUser('agent')) {
            Offer__c sam = OfferController.submitOffer(
                propId,
                'Sam Lowball',
                720000
            );
            Assert.isFalse(OfferController.getOfferContext(propId).canApprove);
            try {
                OfferController.approveOffer(sam.Id);
                Assert.fail('Agents cannot approve');
            } catch (AuraHandledException e) {
                Assert.isTrue(
                    e.getMessage().contains('Approve Offers'),
                    e.getMessage()
                );
            }
            try {
                OfferController.acceptOffer(sam.Id);
                Assert.fail('Needs approval first');
            } catch (AuraHandledException e) {
                Assert.isTrue(e.getMessage().contains('needs broker approval'));
            }
            OfferController.rejectOffer(sam.Id);
            Assert.areEqual(
                OfferService.STATUS_REJECTED,
                [SELECT Status__c FROM Offer__c WHERE Id = :sam.Id].Status__c
            );
        }
    }

    @IsTest
    static void submitErrorsBecomeAuraExceptions() {
        try {
            OfferController.submitOffer(propertyId(), 'Zero', 0);
            Assert.fail('Zero amount should fail');
        } catch (AuraHandledException e) {
            Assert.areEqual(
                'Offer amount must be greater than zero.',
                e.getMessage()
            );
        }
    }

    @IsTest
    static void dmlErrorsShowTheValidationMessage() {
        Offer__c offer = OfferService.submitOffer(
            propertyId(),
            'Jane Buyer',
            820000
        );
        try {
            update new Offer__c(
                Id = offer.Id,
                Status__c = OfferService.STATUS_ACCEPTED
            );
            Assert.fail('Direct status edits are blocked');
        } catch (DmlException e) {
            AuraHandledException auraException = OfferController.toAuraException(
                e
            );
            Assert.isTrue(
                auraException.getMessage()
                    .startsWith('Use Approve, Accept or Reject'),
                auraException.getMessage()
            );
        }
    }

    @IsTest
    static void invalidIdsAreReportedAsAuraExceptions() {
        Id missing =
            Offer__c.SObjectType.getDescribe().getKeyPrefix() +
            '000000000000AAA';
        for (Integer i = 0; i < 3; i++) {
            try {
                if (i == 0) {
                    OfferController.approveOffer(missing);
                } else if (i == 1) {
                    OfferController.acceptOffer(missing);
                } else {
                    OfferController.rejectOffer(missing);
                }
                Assert.fail('Missing offer');
            } catch (AuraHandledException e) {
                Assert.isNotNull(e.getMessage());
            }
        }
        try {
            OfferController.getOfferContext('bad-id');
            Assert.fail('Bad id');
        } catch (Exception e) {
            Assert.isNotNull(e.getMessage());
        }
    }
}
