public with sharing class PropertyOffersController {
    public class OffersView {
        @AuraEnabled
        public List<Offer__c> offers;
        @AuraEnabled
        public Decimal askingPrice;
        @AuraEnabled
        public Boolean canApprove;
        @AuraEnabled
        public String propertyStatus;
    }
    @AuraEnabled(cacheable=true)
    public static OffersView getOffers(Id propertyId) {
        try {
            Property__c property = [
                SELECT Price__c, Status__c
                FROM Property__c
                WHERE Id = :propertyId
                WITH USER_MODE
            ];
            OffersView result = new OffersView();
            result.askingPrice = property.Price__c;
            result.propertyStatus = property.Status__c;
            result.canApprove = OfferService.canApprove();
            result.offers = [
                SELECT
                    Id,
                    Buyer_Name__c,
                    Amount__c,
                    Percent_Below_Asking__c,
                    Status__c
                FROM Offer__c
                WHERE Property__c = :propertyId
                WITH USER_MODE
                ORDER BY CreatedDate DESC, Id DESC
            ];
            return result;
        } catch (Exception e) {
            throw handled(e);
        }
    }
    @AuraEnabled
    public static Id submitOffer(
        Id propertyId,
        String buyerName,
        Decimal amount
    ) {
        try {
            return OfferService.submit(propertyId, buyerName, amount);
        } catch (Exception e) {
            throw handled(e);
        }
    }
    @AuraEnabled
    public static void approveOffer(Id offerId) {
        try {
            OfferService.approve(offerId);
        } catch (Exception e) {
            throw handled(e);
        }
    }
    @AuraEnabled
    public static void acceptOffer(Id offerId) {
        try {
            OfferService.accept(offerId);
        } catch (Exception e) {
            throw handled(e);
        }
    }
    @AuraEnabled
    public static void rejectOffer(Id offerId) {
        try {
            OfferService.reject(offerId);
        } catch (Exception e) {
            throw handled(e);
        }
    }
    private static AuraHandledException handled(Exception e) {
        AuraHandledException error = new AuraHandledException(e.getMessage());
        error.setMessage(e.getMessage());
        return error;
    }
}
