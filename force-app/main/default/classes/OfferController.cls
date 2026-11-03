public with sharing class OfferController {
    public class OfferContext {
        @AuraEnabled
        public Decimal askingPrice;
        @AuraEnabled
        public String propertyStatus;
        @AuraEnabled
        public Boolean canApprove;
        @AuraEnabled
        public Decimal approvalThreshold;
        @AuraEnabled
        public List<OfferRow> offers = new List<OfferRow>();
    }

    public class OfferRow {
        @AuraEnabled
        public Id id;
        @AuraEnabled
        public String buyerName;
        @AuraEnabled
        public Decimal amount;
        @AuraEnabled
        public Decimal percentBelowAsking;
        @AuraEnabled
        public String status;
        @AuraEnabled
        public Boolean requiresApproval;
    }

    @AuraEnabled
    public static OfferContext getOfferContext(Id propertyId) {
        try {
            return buildContext(propertyId);
        } catch (Exception e) {
            throw toAuraException(e);
        }
    }

    @AuraEnabled
    public static OfferContext submitOffer(
        Id propertyId,
        String buyerName,
        Decimal amount
    ) {
        try {
            OfferService.submitOffer(propertyId, buyerName, amount);
            return buildContext(propertyId);
        } catch (Exception e) {
            throw toAuraException(e);
        }
    }

    @AuraEnabled
    public static OfferContext approveOffer(Id propertyId, Id offerId) {
        try {
            OfferService.approveOffer(offerId);
            return buildContext(propertyId);
        } catch (Exception e) {
            throw toAuraException(e);
        }
    }

    @AuraEnabled
    public static OfferContext acceptOffer(Id propertyId, Id offerId) {
        try {
            OfferService.acceptOffer(offerId);
            return buildContext(propertyId);
        } catch (Exception e) {
            throw toAuraException(e);
        }
    }

    @AuraEnabled
    public static OfferContext rejectOffer(Id propertyId, Id offerId) {
        try {
            OfferService.rejectOffer(offerId);
            return buildContext(propertyId);
        } catch (Exception e) {
            throw toAuraException(e);
        }
    }

    private static OfferContext buildContext(Id propertyId) {
        List<Property__c> properties = [
            SELECT
                Id,
                Price__c,
                Status__c,
                (
                    SELECT
                        Id,
                        Buyer_Name__c,
                        Amount__c,
                        Percent_Below_Asking__c,
                        Approved_Percent_Below__c,
                        Status__c
                    FROM Offers__r
                    ORDER BY CreatedDate DESC, Name DESC
                )
            FROM Property__c
            WHERE Id = :propertyId
            WITH USER_MODE
        ];
        if (properties.isEmpty()) {
            throw new OfferService.OfferException('Property not found.');
        }
        Property__c property = properties[0];
        OfferContext context = new OfferContext();
        context.askingPrice = property.Price__c;
        context.propertyStatus = property.Status__c;
        context.canApprove = OfferService.canApprove();
        context.approvalThreshold = OfferService.APPROVAL_THRESHOLD;
        for (Offer__c offer : property.Offers__r) {
            OfferRow row = new OfferRow();
            row.id = offer.Id;
            row.buyerName = offer.Buyer_Name__c;
            row.amount = offer.Amount__c;
            row.percentBelowAsking = offer.Percent_Below_Asking__c;
            row.status = offer.Status__c;
            row.requiresApproval =
                property.Price__c != null &&
                property.Price__c > 0 &&
                OfferService.OPEN_STATUSES.contains(offer.Status__c) &&
                OfferService.requiresApproval(offer, property.Price__c);
            context.offers.add(row);
        }
        return context;
    }

    private static AuraHandledException toAuraException(Exception e) {
        String message = e.getMessage();
        if (e instanceof DmlException) {
            message = ((DmlException) e).getDmlMessage(0);
        }
        AuraHandledException auraException = new AuraHandledException(message);
        auraException.setMessage(message);
        return auraException;
    }
}
