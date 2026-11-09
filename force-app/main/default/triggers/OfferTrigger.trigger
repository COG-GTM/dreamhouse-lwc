trigger OfferTrigger on Offer__c(before insert, before update) {
    if (Trigger.isInsert) {
        OfferService.guardInsert(Trigger.new);
    } else {
        OfferService.guardUpdate(Trigger.new, Trigger.oldMap);
    }
}
