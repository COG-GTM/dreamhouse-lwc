trigger OfferTrigger on Offer__c(before insert, before update) {
    if (Trigger.isInsert) {
        OfferTriggerHandler.beforeInsert(Trigger.new);
    } else {
        OfferTriggerHandler.beforeUpdate(Trigger.new, Trigger.oldMap);
    }
}
