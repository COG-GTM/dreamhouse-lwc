trigger OfferTrigger on Offer__c(before insert, before update) {
    if (Trigger.isInsert) {
        OfferService.applySubmissionRules(Trigger.new);
    } else {
        OfferService.applyUpdateRules(Trigger.new, Trigger.oldMap);
    }
}
