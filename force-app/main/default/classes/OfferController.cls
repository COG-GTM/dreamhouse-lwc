public with sharing class OfferController {
    public class OfferList {
        @AuraEnabled
        public List<Offer__c> offers;
        @AuraEnabled
        public Boolean canApprove;
    }

    @AuraEnabled(cacheable=true)
    public static OfferList getOffers(Id propertyId) {
        try {
            OfferList result = new OfferList();
            result.offers = OfferService.getOffers(propertyId);
            result.canApprove = OfferService.canApprove();
            return result;
        } catch (Exception e) {
            throw auraError(e);
        }
    }

    @AuraEnabled
    public static Offer__c submitOffer(
        Id propertyId,
        String buyerName,
        Decimal amount
    ) {
        try {
            return OfferService.submitOffer(propertyId, buyerName, amount);
        } catch (Exception e) {
            throw auraError(e);
        }
    }

    @AuraEnabled
    public static void approveOffer(Id offerId) {
        try {
            OfferService.approveOffer(offerId);
        } catch (Exception e) {
            throw auraError(e);
        }
    }

    @AuraEnabled
    public static void acceptOffer(Id offerId) {
        try {
            OfferService.acceptOffer(offerId);
        } catch (Exception e) {
            throw auraError(e);
        }
    }

    @AuraEnabled
    public static void rejectOffer(Id offerId) {
        try {
            OfferService.rejectOffer(offerId);
        } catch (Exception e) {
            throw auraError(e);
        }
    }

    private static AuraHandledException auraError(Exception e) {
        AuraHandledException error = new AuraHandledException(e.getMessage());
        error.setMessage(e.getMessage());
        return error;
    }
}
