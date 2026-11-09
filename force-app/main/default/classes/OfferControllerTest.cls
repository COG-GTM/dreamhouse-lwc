@isTest
private class OfferControllerTest {
    @TestSetup
    static void setup() {
        OfferTestFactory.createUsersAndProperty();
    }

    @isTest
    static void agentAndBrokerSeeDifferentApprovalRights() {
        System.runAs(OfferTestFactory.agent()) {
            Assert.isFalse(OfferController.canApprove());
        }
        System.runAs(OfferTestFactory.broker()) {
            Assert.isTrue(OfferController.canApprove());
        }
    }

    @isTest
    static void fullOfferFlowThroughController() {
        Id propertyId = OfferTestFactory.property().Id;
        Offer__c jane;
        Offer__c sam;
        Offer__c late;
        System.runAs(OfferTestFactory.agent()) {
            jane = OfferController.submitOffer(
                propertyId,
                'Jane Buyer',
                820000
            );
            sam = OfferController.submitOffer(
                propertyId,
                'Sam Lowball',
                720000
            );
            late = OfferController.submitOffer(
                propertyId,
                'Late Larry',
                830000
            );
            OfferController.rejectOffer(late.Id);
            Assert.areEqual(3, OfferController.getOffers(propertyId).size());
        }
        System.runAs(OfferTestFactory.broker()) {
            OfferController.approveOffer(sam.Id);
            OfferController.acceptOffer(sam.Id);
        }
        Map<Id, Offer__c> offers = new Map<Id, Offer__c>(
            [SELECT Id, Status__c FROM Offer__c]
        );
        Assert.areEqual('Accepted', offers.get(sam.Id).Status__c);
        Assert.areEqual('Rejected', offers.get(jane.Id).Status__c);
        Assert.areEqual('Rejected', offers.get(late.Id).Status__c);
        Assert.areEqual(
            'Under Agreement',
            OfferTestFactory.property().Status__c
        );
    }

    @isTest
    static void serviceErrorsBecomeAuraHandledExceptions() {
        Id propertyId = OfferTestFactory.property().Id;
        System.runAs(OfferTestFactory.agent()) {
            Offer__c sam = OfferController.submitOffer(
                propertyId,
                'Sam Lowball',
                720000
            );
            assertAuraError(
                new ControllerCall('submit', propertyId),
                'The offer amount must be more than $0.'
            );
            assertAuraError(
                new ControllerCall('approve', sam.Id),
                'Approve Offers'
            );
            assertAuraError(
                new ControllerCall('accept', sam.Id),
                'must approve'
            );
            OfferController.rejectOffer(sam.Id);
            assertAuraError(
                new ControllerCall('reject', sam.Id),
                'Only open offers can be rejected.'
            );
        }
    }

    @isTest
    static void getOffersReportsQueryErrors() {
        Id propertyId = OfferTestFactory.property().Id;
        User noAccess;
        System.runAs(new User(Id = UserInfo.getUserId())) {
            User agent = OfferTestFactory.agent();
            delete [
                SELECT Id
                FROM PermissionSetAssignment
                WHERE
                    AssigneeId = :agent.Id
                    AND PermissionSet.Name = 'dreamhouse'
            ];
            noAccess = agent;
        }
        System.runAs(noAccess) {
            assertAuraError(new ControllerCall('get', propertyId), '');
        }
    }

    @isTest
    static void dmlErrorsUseTheFieldMessage() {
        Id propertyId = OfferTestFactory.property().Id;
        System.runAs(OfferTestFactory.broker()) {
            try {
                insert new Offer__c(
                    Property__c = propertyId,
                    Buyer_Name__c = 'Sneaky',
                    Amount__c = 1
                );
                Assert.fail('Direct insert should be blocked');
            } catch (DmlException e) {
                AuraHandledException aura = OfferController.toAuraException(e);
                Assert.isTrue(aura.getMessage().contains('Offers card'));
                Assert.isFalse(
                    aura.getMessage().contains('FIELD_CUSTOM_VALIDATION')
                );
            }
        }
    }

    private class ControllerCall {
        String action;
        Id recordId;
        ControllerCall(String action, Id recordId) {
            this.action = action;
            this.recordId = recordId;
        }
        void run() {
            switch on action {
                when 'submit' {
                    OfferController.submitOffer(recordId, 'Zero Zack', 0);
                }
                when 'approve' {
                    OfferController.approveOffer(recordId);
                }
                when 'accept' {
                    OfferController.acceptOffer(recordId);
                }
                when 'reject' {
                    OfferController.rejectOffer(recordId);
                }
                when else {
                    OfferController.getOffers(recordId);
                }
            }
        }
    }

    private static void assertAuraError(ControllerCall call, String expected) {
        try {
            call.run();
            Assert.fail('Expected an AuraHandledException for ' + call.action);
        } catch (AuraHandledException e) {
            Assert.isTrue(
                e.getMessage().contains(expected),
                'Unexpected message: ' + e.getMessage()
            );
        }
    }
}
