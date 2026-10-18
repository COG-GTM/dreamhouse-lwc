trigger OfferTrigger on Offer__c(before insert) {
    OfferService.applySubmissionRules(Trigger.new);
}
