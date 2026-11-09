public with sharing class OfferController {
    @AuraEnabled(cacheable=true)
    public static List<Offer__c> getOffers(Id propertyId) {
        try {
            return OfferService.getOffers(propertyId);
        } catch (Exception e) {
            throw toAuraException(e);
        }
    }

    @AuraEnabled(cacheable=true)
    public static Boolean canApprove() {
        return OfferService.canApprove();
    }

    @AuraEnabled
    public static Offer__c submitOffer(
        Id propertyId,
        String buyerName,
        Decimal amount
    ) {
        try {
            return OfferService.submit(propertyId, buyerName, amount);
        } catch (Exception e) {
            throw toAuraException(e);
        }
    }

    @AuraEnabled
    public static void approveOffer(Id offerId) {
        try {
            OfferService.approve(offerId);
        } catch (Exception e) {
            throw toAuraException(e);
        }
    }

    @AuraEnabled
    public static void acceptOffer(Id offerId) {
        try {
            OfferService.accept(offerId);
        } catch (Exception e) {
            throw toAuraException(e);
        }
    }

    @AuraEnabled
    public static void rejectOffer(Id offerId) {
        try {
            OfferService.reject(offerId);
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
