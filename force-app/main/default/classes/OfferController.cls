public with sharing class OfferController {
    public class OfferContext {
        @AuraEnabled
        public Decimal askingPrice;
        @AuraEnabled
        public String propertyStatus;
        @AuraEnabled
        public Boolean canApprove;
        @AuraEnabled
        public Boolean acceptingOffers;
        @AuraEnabled
        public List<Offer__c> offers;
        @AuraEnabled
        public List<Id> approvalRequiredOfferIds = new List<Id>();
    }

    @AuraEnabled
    public static OfferContext getOfferContext(Id propertyId) {
        try {
            List<Property__c> properties = [
                SELECT Price__c, Status__c
                FROM Property__c
                WHERE Id = :propertyId
                WITH USER_MODE
            ];
            if (properties.isEmpty()) {
                throw new OfferService.OfferException('Property not found.');
            }
            OfferContext context = new OfferContext();
            context.askingPrice = properties[0].Price__c;
            context.propertyStatus = properties[0].Status__c;
            context.acceptingOffers = !OfferService.CLOSED_PROPERTY_STATUSES.contains(
                properties[0].Status__c
            );
            context.canApprove = OfferService.canApprove();
            context.offers = [
                SELECT
                    Id,
                    Name,
                    Buyer_Name__c,
                    Amount__c,
                    Percent_Below_Asking__c,
                    Approved_Percent_Below__c,
                    Status__c,
                    CreatedDate
                FROM Offer__c
                WHERE Property__c = :propertyId
                WITH USER_MODE
                ORDER BY CreatedDate DESC, Name DESC
            ];
            if (context.askingPrice != null && context.askingPrice > 0) {
                for (Offer__c offer : context.offers) {
                    if (
                        OfferService.requiresApproval(
                            offer,
                            context.askingPrice
                        )
                    ) {
                        context.approvalRequiredOfferIds.add(offer.Id);
                    }
                }
            }
            return context;
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
    public static Offer__c approveOffer(Id offerId) {
        try {
            return OfferService.approveOffer(offerId);
        } catch (Exception e) {
            throw auraError(e);
        }
    }

    @AuraEnabled
    public static Offer__c acceptOffer(Id offerId) {
        try {
            return OfferService.acceptOffer(offerId);
        } catch (Exception e) {
            throw auraError(e);
        }
    }

    @AuraEnabled
    public static Offer__c rejectOffer(Id offerId) {
        try {
            return OfferService.rejectOffer(offerId);
        } catch (Exception e) {
            throw auraError(e);
        }
    }

    private static AuraHandledException auraError(Exception e) {
        String message = e.getMessage();
        if (e instanceof DmlException) {
            message = ((DmlException) e).getDmlMessage(0);
        }
        AuraHandledException error = new AuraHandledException(message);
        error.setMessage(message);
        return error;
    }
}
