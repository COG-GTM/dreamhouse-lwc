public with sharing class OfferController {
    @AuraEnabled
    public static OfferService.OfferContext getOfferContext(Id propertyId) {
        try {
            return OfferService.getOfferContext(propertyId);
        } catch (Exception e) {
            throw toAuraException(e);
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
            throw toAuraException(e);
        }
    }

    @AuraEnabled
    public static void approveOffer(Id offerId) {
        try {
            OfferService.approveOffer(offerId);
        } catch (Exception e) {
            throw toAuraException(e);
        }
    }

    @AuraEnabled
    public static void acceptOffer(Id offerId) {
        try {
            OfferService.acceptOffer(offerId);
        } catch (Exception e) {
            throw toAuraException(e);
        }
    }

    @AuraEnabled
    public static void rejectOffer(Id offerId) {
        try {
            OfferService.rejectOffer(offerId);
        } catch (Exception e) {
            throw toAuraException(e);
        }
    }

    @TestVisible
    private static AuraHandledException toAuraException(Exception e) {
        String message = e instanceof DmlException
            ? ((DmlException) e).getDmlMessage(0)
            : e.getMessage();
        AuraHandledException auraException = new AuraHandledException(message);
        auraException.setMessage(message);
        return auraException;
    }
}
