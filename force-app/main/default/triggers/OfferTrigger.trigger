trigger OfferTrigger on Offer__c(before insert, before update) {
    if (Trigger.isInsert) {
        OfferService.validateBeforeInsert(Trigger.new);
    } else {
        OfferService.validateBeforeUpdate(Trigger.new, Trigger.oldMap);
    }
}
