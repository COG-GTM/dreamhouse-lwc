trigger OfferTrigger on Offer__c(before insert, before update) {
    if (Trigger.isInsert) {
        OfferService.handleBeforeInsert(Trigger.new);
    } else {
        OfferService.handleBeforeUpdate(Trigger.new, Trigger.oldMap);
    }
}
