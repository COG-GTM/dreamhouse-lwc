trigger OfferTrigger on Offer__c(before insert, before update) {
    if (Trigger.isInsert) {
        OfferService.enforceOnInsert(Trigger.new);
    } else {
        OfferService.enforceOnUpdate(Trigger.new, Trigger.oldMap);
    }
}
