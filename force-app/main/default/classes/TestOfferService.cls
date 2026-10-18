@isTest
private class TestOfferService {
    private static Property__c createProperty(Decimal price, String status) {
        Property__c property = new Property__c(
            Name = 'Test Property',
            Price__c = price,
            Status__c = status
        );
        insert property;
        return property;
    }

    private static Offer__c submit(Id propertyId, Decimal amount) {
        Offer__c offer = new Offer__c(
            Property__c = propertyId,
            Buyer_Name__c = 'Jane Buyer',
            Amount__c = amount
        );
        insert offer;
        return [
            SELECT Id, Status__c, Discount_Percent__c
            FROM Offer__c
            WHERE Id = :offer.Id
        ];
    }

    @isTest
    static void testDiscountPercent() {
        Assert.areEqual(10.0, OfferService.discountPercent(500000, 450000));
        Assert.areEqual(-5.0, OfferService.discountPercent(400000, 420000));
        Assert.areEqual(0, OfferService.discountPercent(null, 450000));
        Assert.areEqual(0, OfferService.discountPercent(0, 450000));
    }

    @isTest
    static void testOfferWithinThresholdIsSubmitted() {
        Property__c property = createProperty(500000, 'Available');

        Test.startTest();
        Offer__c offer = submit(property.Id, 450000);
        Test.stopTest();

        Assert.areEqual(OfferService.STATUS_SUBMITTED, offer.Status__c);
        Assert.areEqual(10.0, offer.Discount_Percent__c);
    }

    @isTest
    static void testDeepDiscountNeedsApproval() {
        Property__c property = createProperty(500000, 'Available');

        Test.startTest();
        Offer__c offer = submit(property.Id, 440000);
        Test.stopTest();

        Assert.areEqual(OfferService.STATUS_NEEDS_APPROVAL, offer.Status__c);
        Assert.areEqual(12.0, offer.Discount_Percent__c);
    }

    @isTest
    static void testOfferOnClosedPropertyIsBlocked() {
        Property__c property = createProperty(500000, 'Closed');

        Test.startTest();
        Database.SaveResult result = Database.insert(
            new Offer__c(
                Property__c = property.Id,
                Buyer_Name__c = 'Jane Buyer',
                Amount__c = 480000
            ),
            false
        );
        Test.stopTest();

        Assert.isFalse(result.isSuccess());
        Assert.isTrue(result.getErrors()[0].getMessage().contains('Closed'));
    }

    @isTest
    static void testNonPositiveAmountIsBlocked() {
        Property__c property = createProperty(500000, 'Available');

        Test.startTest();
        Database.SaveResult result = Database.insert(
            new Offer__c(
                Property__c = property.Id,
                Buyer_Name__c = 'Jane Buyer',
                Amount__c = 0
            ),
            false
        );
        Test.stopTest();

        Assert.isFalse(result.isSuccess());
    }

    @isTest
    static void testAcceptRejectsOtherOffersAndUpdatesProperty() {
        Property__c property = createProperty(500000, 'Available');
        Offer__c winner = submit(property.Id, 490000);
        Offer__c other = submit(property.Id, 470000);

        Test.startTest();
        OfferService.accept(winner.Id);
        Test.stopTest();

        Assert.areEqual(
            OfferService.STATUS_ACCEPTED,
            [SELECT Status__c FROM Offer__c WHERE Id = :winner.Id].Status__c
        );
        Assert.areEqual(
            OfferService.STATUS_REJECTED,
            [SELECT Status__c FROM Offer__c WHERE Id = :other.Id].Status__c
        );
        Property__c updated = [
            SELECT Status__c, Date_Agreement__c
            FROM Property__c
            WHERE Id = :property.Id
        ];
        Assert.areEqual('Under Agreement', updated.Status__c);
        Assert.areEqual(Date.today(), updated.Date_Agreement__c);
    }

    @isTest
    static void testCannotAcceptOfferThatNeedsApproval() {
        Property__c property = createProperty(500000, 'Available');
        Offer__c offer = submit(property.Id, 400000);

        Test.startTest();
        try {
            OfferService.accept(offer.Id);
            Assert.fail('Expected OfferException');
        } catch (OfferService.OfferException e) {
            Assert.isTrue(e.getMessage().contains('needs broker approval'));
        }
        Test.stopTest();
    }

    @isTest
    static void testRejectClosedOfferFails() {
        Property__c property = createProperty(500000, 'Available');
        Offer__c offer = submit(property.Id, 480000);
        OfferService.reject(offer.Id);

        Test.startTest();
        try {
            OfferService.reject(offer.Id);
            Assert.fail('Expected OfferException');
        } catch (OfferService.OfferException e) {
            Assert.isTrue(e.getMessage().contains('already closed'));
        }
        Test.stopTest();
    }

    @isTest
    static void testOfferOnUnderAgreementPropertyIsBlocked() {
        Property__c property = createProperty(500000, 'Under Agreement');

        Test.startTest();
        Database.SaveResult result = Database.insert(
            new Offer__c(
                Property__c = property.Id,
                Buyer_Name__c = 'Late Buyer',
                Amount__c = 500000
            ),
            false
        );
        Test.stopTest();

        Assert.isFalse(result.isSuccess());
        Assert.isTrue(
            result.getErrors()[0].getMessage().contains('Under Agreement')
        );
    }

    @isTest
    static void testCannotAcceptOfferAfterPropertyCloses() {
        Property__c property = createProperty(500000, 'Available');
        Offer__c offer = submit(property.Id, 490000);
        property.Status__c = 'Closed';
        update property;

        Test.startTest();
        try {
            OfferService.accept(offer.Id);
            Assert.fail('Expected OfferException');
        } catch (OfferService.OfferException e) {
            Assert.isTrue(e.getMessage().contains('Closed'));
        }
        Test.stopTest();

        Assert.areEqual(
            'Closed',
            [SELECT Status__c FROM Property__c WHERE Id = :property.Id]
            .Status__c
        );
    }

    @isTest
    static void testDirectStatusEditIsBlocked() {
        Property__c property = createProperty(500000, 'Available');
        Offer__c offer = submit(property.Id, 400000);

        Test.startTest();
        Database.SaveResult result = Database.update(
            new Offer__c(Id = offer.Id, Status__c = 'Accepted'),
            false
        );
        Test.stopTest();

        Assert.isFalse(result.isSuccess());
        Assert.areEqual(
            'Needs Approval',
            [SELECT Status__c FROM Offer__c WHERE Id = :offer.Id].Status__c
        );
    }

    @isTest
    static void testAmountEditIsBlocked() {
        Property__c property = createProperty(500000, 'Available');
        Offer__c offer = submit(property.Id, 480000);

        Test.startTest();
        Database.SaveResult result = Database.update(
            new Offer__c(Id = offer.Id, Amount__c = 400000),
            false
        );
        Test.stopTest();

        Assert.isFalse(result.isSuccess());
    }
}
