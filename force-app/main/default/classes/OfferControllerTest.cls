@IsTest
private class OfferControllerTest {
    private enum Action {
        SUBMIT,
        APPROVE,
        ACCEPT,
        REJECT,
        CONTEXT
    }

    @TestSetup
    static void setup() {
        OfferTestFactory.createUsers();
        OfferTestFactory.createProperty('Controller Home', 845000, 'Available');
    }

    private static Id propertyId() {
        return [SELECT Id FROM Property__c WHERE Name = 'Controller Home'].Id;
    }

    @IsTest
    static void contextReflectsAgentPermissions() {
        System.runAs(OfferTestFactory.agent()) {
            OfferController.submitOffer(propertyId(), 'Jane Buyer', 820000);
            OfferController.OfferContext context = OfferController.getOfferContext(
                propertyId()
            );
            Assert.areEqual(845000, context.askingPrice);
            Assert.areEqual('Available', context.propertyStatus);
            Assert.isTrue(context.acceptingOffers);
            Assert.isFalse(context.canApprove);
            Assert.areEqual(1, context.offers.size());
            Assert.areEqual('Jane Buyer', context.offers[0].Buyer_Name__c);
        }
    }

    @IsTest
    static void brokerRunsTheFullApprovalFlow() {
        System.runAs(OfferTestFactory.broker()) {
            Id propId = propertyId();
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
            Assert.isTrue(OfferController.getOfferContext(propId).canApprove);

            Assert.areEqual(
                'Approved',
                OfferController.approveOffer(sam.Id).Status__c
            );
            Assert.areEqual(
                'Accepted',
                OfferController.acceptOffer(sam.Id).Status__c
            );

            OfferController.OfferContext context = OfferController.getOfferContext(
                propId
            );
            Assert.areEqual('Under Agreement', context.propertyStatus);
            Assert.isFalse(context.acceptingOffers);
            Map<Id, String> statuses = new Map<Id, String>();
            for (Offer__c offer : context.offers) {
                statuses.put(offer.Id, offer.Status__c);
            }
            Assert.areEqual('Rejected', statuses.get(jane.Id));
            Assert.areEqual('Accepted', statuses.get(sam.Id));
        }
    }

    @IsTest
    static void rejectThroughController() {
        System.runAs(OfferTestFactory.agent()) {
            Offer__c offer = OfferController.submitOffer(
                propertyId(),
                'Jane Buyer',
                820000
            );
            Assert.areEqual(
                'Rejected',
                OfferController.rejectOffer(offer.Id).Status__c
            );
        }
    }

    @IsTest
    static void errorsAreReturnedAsAuraHandledExceptions() {
        System.runAs(OfferTestFactory.agent()) {
            Offer__c sam = OfferController.submitOffer(
                propertyId(),
                'Sam Lowball',
                720000
            );
            assertAuraError(
                new Runner(Action.SUBMIT, propertyId()),
                'greater than zero'
            );
            assertAuraError(
                new Runner(Action.APPROVE, sam.Id),
                'Approve Offers'
            );
            assertAuraError(
                new Runner(Action.ACCEPT, sam.Id),
                'needs broker approval'
            );
            OfferController.rejectOffer(sam.Id);
            assertAuraError(
                new Runner(Action.REJECT, sam.Id),
                'already closed'
            );
        }
    }

    @IsTest
    static void unknownPropertyIsReported() {
        Id missing = propertyId();
        delete new Property__c(Id = missing);
        assertAuraError(new Runner(Action.CONTEXT, missing), 'not found');
    }

    @IsTest
    static void dmlErrorsUseTheDmlMessage() {
        try {
            OfferController.submitOffer(propertyId(), 'x'.repeat(130), 800000);
            Assert.fail('Expected an AuraHandledException');
        } catch (AuraHandledException e) {
            Assert.isFalse(e.getMessage().contains('Insert failed'));
            Assert.isTrue(String.isNotBlank(e.getMessage()));
        }
    }

    private static void assertAuraError(Runner runner, String expected) {
        try {
            runner.run();
            Assert.fail('Expected an AuraHandledException');
        } catch (AuraHandledException e) {
            Assert.isTrue(
                e.getMessage().contains(expected),
                'Unexpected message: ' + e.getMessage()
            );
        }
    }

    private class Runner {
        Action action;
        Id recordId;

        Runner(Action action, Id recordId) {
            this.action = action;
            this.recordId = recordId;
        }

        void run() {
            switch on action {
                when SUBMIT {
                    OfferController.submitOffer(recordId, 'Buyer', 0);
                }
                when APPROVE {
                    OfferController.approveOffer(recordId);
                }
                when ACCEPT {
                    OfferController.acceptOffer(recordId);
                }
                when REJECT {
                    OfferController.rejectOffer(recordId);
                }
                when CONTEXT {
                    OfferController.getOfferContext(recordId);
                }
            }
        }
    }
}
