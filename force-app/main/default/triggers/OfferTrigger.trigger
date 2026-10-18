trigger OfferTrigger on Offer__c(before insert, before update) {
    if (Trigger.isInsert) {
        OfferService.applySubmissionRules(Trigger.new);
    } else {
        OfferService.enforceUpdateRules(Trigger.new, Trigger.oldMap);
    }
}
