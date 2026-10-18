@isTest
private class OfferControllerTest {
    @testSetup
    static void setup() {
        insert new Property__c(
            Name = 'Controller House',
            Price__c = 845000,
            Status__c = 'Available'
        );
        System.runAs(new User(Id = UserInfo.getUserId())) {
            OfferServiceTest.createUser('cagent', false);
            OfferServiceTest.createUser('cbroker', true);
        }
    }

    private static Id propertyId() {
        return [SELECT Id FROM Property__c LIMIT 1].Id;
    }

    @isTest
    static void getOffersReportsApprovalPermission() {
        Id propId = propertyId();
        System.runAs(OfferServiceTest.getUser('cagent')) {
            OfferController.submitOffer(propId, 'Jane Buyer', 820000);
            OfferController.OfferList result = OfferController.getOffers(
                propId
            );
            Assert.areEqual(1, result.offers.size());
            Assert.isFalse(result.canApprove);
        }
        System.runAs(OfferServiceTest.getUser('cbroker')) {
            Assert.isTrue(OfferController.getOffers(propId).canApprove);
        }
    }

    @isTest
    static void fullApprovalFlowThroughController() {
        Id propId = propertyId();
        System.runAs(OfferServiceTest.getUser('cbroker')) {
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
            Assert.areEqual('Needs Approval', sam.Status__c);
            OfferController.approveOffer(sam.Id);
            OfferController.acceptOffer(sam.Id);
            Map<Id, Offer__c> offers = new Map<Id, Offer__c>(
                OfferController.getOffers(propId).offers
            );
            Assert.areEqual('Accepted', offers.get(sam.Id).Status__c);
            Assert.areEqual('Rejected', offers.get(jane.Id).Status__c);
        }
    }

    @isTest
    static void rejectThroughController() {
        Id propId = propertyId();
        System.runAs(OfferServiceTest.getUser('cagent')) {
            Offer__c offer = OfferController.submitOffer(
                propId,
                'Jane Buyer',
                820000
            );
            OfferController.rejectOffer(offer.Id);
            Assert.areEqual(
                'Rejected',
                OfferController.getOffers(propId).offers[0].Status__c
            );
        }
    }

    @isTest
    static void errorsAreReturnedAsAuraHandledExceptions() {
        Id propId = propertyId();
        System.runAs(OfferServiceTest.getUser('cagent')) {
            Offer__c sam = OfferController.submitOffer(
                propId,
                'Sam Lowball',
                720000
            );
            assertAuraError(new ApproveCall(sam.Id), 'Approve Offers');
            assertAuraError(new AcceptCall(sam.Id), 'must be approved');
            assertAuraError(new SubmitCall(propId), 'zero');
            OfferController.rejectOffer(sam.Id);
            assertAuraError(new RejectCall(sam.Id), 'open offers');
        }
    }

    private interface ControllerCall {
        void run();
    }
    private class ApproveCall implements ControllerCall {
        Id offerId;
        ApproveCall(Id offerId) {
            this.offerId = offerId;
        }
        public void run() {
            OfferController.approveOffer(offerId);
        }
    }
    private class AcceptCall implements ControllerCall {
        Id offerId;
        AcceptCall(Id offerId) {
            this.offerId = offerId;
        }
        public void run() {
            OfferController.acceptOffer(offerId);
        }
    }
    private class RejectCall implements ControllerCall {
        Id offerId;
        RejectCall(Id offerId) {
            this.offerId = offerId;
        }
        public void run() {
            OfferController.rejectOffer(offerId);
        }
    }
    private class SubmitCall implements ControllerCall {
        Id propertyId;
        SubmitCall(Id propertyId) {
            this.propertyId = propertyId;
        }
        public void run() {
            OfferController.submitOffer(propertyId, 'Zero', 0);
        }
    }
    private static void assertAuraError(ControllerCall call, String expected) {
        try {
            call.run();
            Assert.fail('Expected an AuraHandledException');
        } catch (AuraHandledException e) {
            Assert.isTrue(
                e.getMessage().contains(expected),
                'Unexpected message: ' + e.getMessage()
            );
        }
    }
}
