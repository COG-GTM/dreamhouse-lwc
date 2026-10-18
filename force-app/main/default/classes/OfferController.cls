public with sharing class OfferController {
    /**
     * Offers on a property, newest first.
     */
    @AuraEnabled(cacheable=true)
    public static List<Offer__c> getOffers(Id propertyId) {
        return [
            SELECT
                Id,
                Name,
                Buyer_Name__c,
                Amount__c,
                Discount_Percent__c,
                Status__c,
                CreatedDate
            FROM Offer__c
            WHERE Property__c = :propertyId
            WITH USER_MODE
            ORDER BY CreatedDate DESC, Name DESC
        ];
    }

    @AuraEnabled(cacheable=true)
    public static Boolean canApproveOffers() {
        return FeatureManagement.checkPermission('Approve_Offers');
    }

    @AuraEnabled
    public static Offer__c submitOffer(
        Id propertyId,
        String buyerName,
        Decimal amount
    ) {
        Offer__c offer = new Offer__c(
            Property__c = propertyId,
            Buyer_Name__c = buyerName?.trim(),
            Amount__c = amount
        );
        try {
            insert as user offer;
        } catch (DmlException e) {
            throw toAuraException(e.getDmlMessage(0));
        }
        return offer;
    }

    @AuraEnabled
    public static Offer__c approveOffer(Id offerId) {
        return run(offerId, 'approve');
    }

    @AuraEnabled
    public static Offer__c acceptOffer(Id offerId) {
        return run(offerId, 'accept');
    }

    @AuraEnabled
    public static Offer__c rejectOffer(Id offerId) {
        return run(offerId, 'reject');
    }

    private static Offer__c run(Id offerId, String action) {
        try {
            switch on action {
                when 'approve' {
                    return OfferService.approve(offerId);
                }
                when 'accept' {
                    return OfferService.accept(offerId);
                }
                when else {
                    return OfferService.reject(offerId);
                }
            }
        } catch (OfferService.OfferException e) {
            throw toAuraException(e.getMessage());
        } catch (DmlException e) {
            throw toAuraException(e.getDmlMessage(0));
        }
    }

    private static AuraHandledException toAuraException(String message) {
        AuraHandledException e = new AuraHandledException(message);
        e.setMessage(message);
        return e;
    }
}
