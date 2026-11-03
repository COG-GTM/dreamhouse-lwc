@isTest
private class TestOfferController {
    @isTest
    static void agentSeesOffersWithoutApproveRights() {
        Property__c property = TestOfferService.createProperty('Available');
        User agent = TestOfferService.createUser(false);
        System.runAs(agent) {
            Test.startTest();
            OfferController.OfferContext context = OfferController.submitOffer(
                property.Id,
                'Jane Buyer',
                820000
            );
            context = OfferController.submitOffer(
                property.Id,
                'Sam Lowball',
                720000
            );
            Test.stopTest();
            Assert.areEqual(845000, context.askingPrice);
            Assert.areEqual('Available', context.propertyStatus);
            Assert.isFalse(context.canApprove);
            Assert.areEqual(10, context.approvalThreshold);
            Assert.areEqual(2, context.offers.size());
            Map<String, OfferController.OfferRow> byBuyer = new Map<String, OfferController.OfferRow>();
            for (OfferController.OfferRow row : context.offers) {
                byBuyer.put(row.buyerName, row);
            }
            Assert.areEqual('Submitted', byBuyer.get('Jane Buyer').status);
            Assert.isFalse(byBuyer.get('Jane Buyer').requiresApproval);
            Assert.areEqual(
                'Needs Approval',
                byBuyer.get('Sam Lowball').status
            );
            Assert.isTrue(byBuyer.get('Sam Lowball').requiresApproval);
            Assert.areEqual(
                14.8,
                byBuyer.get('Sam Lowball').percentBelowAsking
            );
            try {
                OfferController.approveOffer(
                    property.Id,
                    byBuyer.get('Sam Lowball').id
                );
                Assert.fail('Agent should not approve');
            } catch (AuraHandledException e) {
                Assert.isTrue(e.getMessage().contains('Approve Offers'));
            }
        }
    }

    @isTest
    static void brokerApprovesAcceptsAndRejects() {
        Property__c property = TestOfferService.createProperty('Available');
        User broker = TestOfferService.createUser(true);
        System.runAs(broker) {
            OfferController.submitOffer(property.Id, 'Jane Buyer', 820000);
            OfferController.submitOffer(property.Id, 'Pat Pass', 830000);
            OfferController.OfferContext context = OfferController.submitOffer(
                property.Id,
                'Sam Lowball',
                720000
            );
            Assert.isTrue(context.canApprove);
            Map<String, Id> ids = new Map<String, Id>();
            for (OfferController.OfferRow row : context.offers) {
                ids.put(row.buyerName, row.id);
            }
            Test.startTest();
            context = OfferController.rejectOffer(
                property.Id,
                ids.get('Pat Pass')
            );
            context = OfferController.approveOffer(
                property.Id,
                ids.get('Sam Lowball')
            );
            context = OfferController.acceptOffer(
                property.Id,
                ids.get('Sam Lowball')
            );
            Test.stopTest();
            Assert.areEqual('Under Agreement', context.propertyStatus);
            for (OfferController.OfferRow row : context.offers) {
                Assert.areEqual(
                    row.buyerName == 'Sam Lowball' ? 'Accepted' : 'Rejected',
                    row.status
                );
                Assert.isFalse(row.requiresApproval);
            }
        }
    }

    @isTest
    static void errorsBecomeAuraHandledExceptions() {
        Property__c property = TestOfferService.createProperty('Closed');
        try {
            OfferController.submitOffer(property.Id, 'Jane', 800000);
            Assert.fail('Closed property');
        } catch (AuraHandledException e) {
            Assert.areEqual(
                'Offers are closed: the property is Closed.',
                e.getMessage()
            );
        }
        Property__c open = TestOfferService.createProperty('Available');
        Id offerId = OfferService.submitOffer(open.Id, 'A', 800000).Id;
        try {
            OfferController.acceptOffer(open.Id, offerId);
            OfferController.rejectOffer(open.Id, offerId);
            Assert.fail('Property is under agreement');
        } catch (AuraHandledException e) {
            Assert.isTrue(e.getMessage().contains('Under Agreement'));
        }
        Id deletedId = open.Id;
        delete open;
        try {
            OfferController.getOfferContext(deletedId);
            Assert.fail('Property deleted');
        } catch (AuraHandledException e) {
            Assert.areEqual('Property not found.', e.getMessage());
        }
    }

    @isTest
    static void dmlErrorsUseFirstDmlMessage() {
        Property__c property = new Property__c(
            Name = 'Long Name Test',
            Price__c = 1000,
            Status__c = 'Available'
        );
        insert property;
        try {
            OfferController.submitOffer(property.Id, 'X'.repeat(200), 900);
            Assert.fail('Buyer name too long');
        } catch (AuraHandledException e) {
            Assert.areEqual(OfferController.GENERIC_ERROR, e.getMessage());
        }
    }

    @isTest
    static void offerMustBelongToProperty() {
        Property__c propertyA = TestOfferService.createProperty('Available');
        Property__c propertyB = TestOfferService.createProperty('Available');
        Id offerOnB = OfferService.submitOffer(propertyB.Id, 'B', 820000).Id;
        try {
            OfferController.acceptOffer(propertyA.Id, offerOnB);
            Assert.fail('Mismatched property');
        } catch (AuraHandledException e) {
            Assert.areEqual(
                'Offer not found on this property.',
                e.getMessage()
            );
        }
        Assert.areEqual(
            'Available',
            [SELECT Status__c FROM Property__c WHERE Id = :propertyB.Id]
            .Status__c
        );
    }

    @isTest
    static void showsCurrentAndSubmittedDiscountAfterPriceChange() {
        Property__c property = TestOfferService.createProperty('Available');
        OfferService.submitOffer(property.Id, 'Jane Buyer', 820000);
        update new Property__c(Id = property.Id, Price__c = 1000000);
        OfferController.OfferRow row = OfferController.getOfferContext(
                property.Id
            )
            .offers[0];
        Assert.areEqual(18.0, row.percentBelowAsking);
        Assert.areEqual(3.0, row.submittedPercentBelowAsking);
        Assert.isTrue(row.requiresApproval);
    }
}
