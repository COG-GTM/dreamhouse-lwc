@isTest
private class OfferControllerTest {
    @testSetup
    static void setup() {
        OfferTestFactory.createUsersAndProperty();
    }

    @isTest
    static void brokerFlowThroughController() {
        Property__c property = OfferTestFactory.property();
        Offer__c jane;
        Offer__c sam;
        System.runAs(OfferTestFactory.agent()) {
            jane = OfferController.submitOffer(
                property.Id,
                'Jane Buyer',
                820000
            );
            sam = OfferController.submitOffer(
                property.Id,
                'Sam Lowball',
                720000
            );
            OfferService.OfferContext context = OfferController.getOfferContext(
                property.Id
            );
            Assert.areEqual(2, context.offers.size());
            Assert.isFalse(context.canApprove);
        }
        System.runAs(OfferTestFactory.broker()) {
            OfferController.approveOffer(sam.Id);
            OfferController.acceptOffer(sam.Id);
        }
        Assert.areEqual(
            OfferService.STATUS_ACCEPTED,
            OfferTestFactory.offer(sam.Id).Status__c
        );
        Assert.areEqual(
            OfferService.STATUS_REJECTED,
            OfferTestFactory.offer(jane.Id).Status__c
        );
        Assert.areEqual(
            'Under Agreement',
            OfferTestFactory.property().Status__c
        );
    }

    @isTest
    static void agentApproveIsReturnedAsAuraHandledException() {
        Property__c property = OfferTestFactory.property();
        System.runAs(OfferTestFactory.agent()) {
            Offer__c sam = OfferController.submitOffer(
                property.Id,
                'Sam',
                720000
            );
            try {
                OfferController.approveOffer(sam.Id);
                Assert.fail('Agent approve should fail');
            } catch (AuraHandledException e) {
                Assert.isTrue(e.getMessage().contains('Approve Offers'));
            }
        }
    }

    @isTest
    static void serviceErrorsAreReturnedAsAuraHandledException() {
        Property__c property = OfferTestFactory.property();
        System.runAs(OfferTestFactory.agent()) {
            Offer__c sam = OfferController.submitOffer(
                property.Id,
                'Sam',
                720000
            );
            assertAuraError(new AcceptAction(sam.Id), 'needs broker approval');
            OfferController.rejectOffer(sam.Id);
            assertAuraError(new RejectAction(sam.Id), 'open offers');
            try {
                OfferController.submitOffer(property.Id, 'Jane', 0);
                Assert.fail('Zero amount should fail');
            } catch (AuraHandledException e) {
                Assert.isTrue(e.getMessage().contains('greater than zero'));
            }
        }
        delete property;
        System.runAs(OfferTestFactory.agent()) {
            try {
                OfferController.getOfferContext(property.Id);
                Assert.fail('Deleted property should fail');
            } catch (AuraHandledException e) {
                Assert.isNotNull(e.getMessage());
            }
        }
    }

    @isTest
    static void dmlErrorsUseTheFirstDmlMessage() {
        Property__c property = OfferTestFactory.property();
        try {
            insert new Offer__c(
                Property__c = property.Id,
                Buyer_Name__c = 'Sneaky',
                Amount__c = 100
            );
            Assert.fail('Direct insert should fail');
        } catch (DmlException e) {
            AuraHandledException auraException = OfferController.toAuraException(
                e
            );
            Assert.isTrue(auraException.getMessage().contains('Offers card'));
            Assert.isFalse(auraException.getMessage().contains('FIELD_CUSTOM'));
        }
    }

    private interface OfferAction {
        void run();
    }

    private class AcceptAction implements OfferAction {
        private Id offerId;
        AcceptAction(Id offerId) {
            this.offerId = offerId;
        }
        public void run() {
            OfferController.acceptOffer(offerId);
        }
    }

    private class RejectAction implements OfferAction {
        private Id offerId;
        RejectAction(Id offerId) {
            this.offerId = offerId;
        }
        public void run() {
            OfferController.rejectOffer(offerId);
        }
    }

    private static void assertAuraError(OfferAction action, String expected) {
        try {
            action.run();
            Assert.fail('Expected error: ' + expected);
        } catch (AuraHandledException e) {
            Assert.isTrue(e.getMessage().contains(expected), e.getMessage());
        }
    }
}
