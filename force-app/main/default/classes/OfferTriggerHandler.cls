public with sharing class OfferTriggerHandler {
    public static void beforeInsert(List<Offer__c> offers) {
        Set<Id> propertyIds = new Set<Id>();
        for (Offer__c offer : offers) {
            propertyIds.add(offer.Property__c);
        }
        Map<Id, Property__c> properties = new Map<Id, Property__c>(
            [
                SELECT Id, Price__c, Status__c
                FROM Property__c
                WHERE Id IN :propertyIds
                WITH USER_MODE
            ]
        );
        for (Offer__c offer : offers) {
            Property__c property = properties.get(offer.Property__c);
            if (
                property == null ||
                property.Price__c == null ||
                property.Price__c <= 0
            ) {
                offer.addError(
                    'A property with a positive asking price is required.'
                );
            } else if (
                property.Status__c == 'Closed' ||
                property.Status__c == 'Under Agreement'
            ) {
                offer.addError('This property is no longer available.');
            } else if (
                String.isBlank(offer.Buyer_Name__c) ||
                offer.Amount__c == null ||
                offer.Amount__c <= 0
            ) {
                offer.addError(
                    'Buyer name and a positive offer amount are required.'
                );
            } else {
                offer.Percent_Below_Asking__c = ((property.Price__c -
                    offer.Amount__c) /
                    property.Price__c *
                    100)
                    .setScale(1, RoundingMode.HALF_UP);
                offer.Status__c = offer.Percent_Below_Asking__c > 10
                    ? 'Needs Approval'
                    : 'Submitted';
            }
        }
    }
    public static void beforeUpdate(
        List<Offer__c> offers,
        Map<Id, Offer__c> oldOffers
    ) {
        for (Offer__c offer : offers) {
            Offer__c previous = oldOffers.get(offer.Id);
            if (
                offer.Amount__c != previous.Amount__c ||
                offer.Percent_Below_Asking__c !=
                previous.Percent_Below_Asking__c
            ) {
                offer.addError(
                    'Offer amount and percent below asking cannot be changed.'
                );
            }
            if (
                offer.Status__c != previous.Status__c &&
                !OfferService.isChangingStatus()
            ) {
                offer.addError('Use the offer actions to change status.');
            }
        }
    }
}
