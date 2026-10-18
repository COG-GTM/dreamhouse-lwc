/**
 * Business rules for buyer offers on a property.
 */
public with sharing class OfferService {
    public static final Decimal APPROVAL_THRESHOLD_PERCENT = 10;

    public static final String STATUS_SUBMITTED = 'Submitted';
    public static final String STATUS_NEEDS_APPROVAL = 'Needs Approval';
    public static final String STATUS_APPROVED = 'Approved';
    public static final String STATUS_ACCEPTED = 'Accepted';
    public static final String STATUS_REJECTED = 'Rejected';

    public static final String PROPERTY_STATUS_CLOSED = 'Closed';
    public static final String PROPERTY_STATUS_UNDER_AGREEMENT = 'Under Agreement';

    public class OfferException extends Exception {
    }

    // Status changes are only allowed through approve/accept/reject, never by direct edit.
    private static Boolean statusChangeAllowed = false;

    /**
     * Percentage the offer is below the asking price (negative when above asking).
     */
    public static Decimal discountPercent(Decimal askingPrice, Decimal amount) {
        if (askingPrice == null || askingPrice <= 0 || amount == null) {
            return 0;
        }
        return ((askingPrice - amount) / askingPrice * 100).setScale(1);
    }

    /**
     * Validates new offers, stamps the discount and routes deep discounts to approval.
     */
    public static void applySubmissionRules(List<Offer__c> offers) {
        Set<Id> propertyIds = new Set<Id>();
        for (Offer__c offer : offers) {
            propertyIds.add(offer.Property__c);
        }
        Map<Id, Property__c> properties;
        try {
            properties = new Map<Id, Property__c>(
                [
                    SELECT Id, Price__c, Status__c
                    FROM Property__c
                    WHERE Id IN :propertyIds
                    WITH USER_MODE
                ]
            );
        } catch (QueryException e) {
            for (Offer__c offer : offers) {
                offer.addError(
                    'You need access to the property asking price to submit offers.'
                );
            }
            return;
        }

        for (Offer__c offer : offers) {
            Property__c property = properties.get(offer.Property__c);
            if (offer.Amount__c == null || offer.Amount__c <= 0) {
                offer.Amount__c.addError(
                    'Offer amount must be greater than zero.'
                );
                continue;
            }
            if (property == null) {
                continue;
            }
            if (!isOpenForOffers(property)) {
                offer.addError(
                    'Offers cannot be submitted on a property that is ' +
                        property.Status__c +
                        '.'
                );
                continue;
            }
            offer.Discount_Percent__c = discountPercent(
                property.Price__c,
                offer.Amount__c
            );
            offer.Status__c = offer.Discount_Percent__c >
                APPROVAL_THRESHOLD_PERCENT
                ? STATUS_NEEDS_APPROVAL
                : STATUS_SUBMITTED;
        }
    }

    /**
     * Blocks direct edits that would bypass the approval rules.
     */
    public static void applyUpdateRules(
        List<Offer__c> offers,
        Map<Id, Offer__c> oldOffers
    ) {
        for (Offer__c offer : offers) {
            Offer__c old = oldOffers.get(offer.Id);
            if (
                offer.Amount__c != old.Amount__c ||
                offer.Discount_Percent__c != old.Discount_Percent__c
            ) {
                offer.addError(
                    'An offer amount cannot be changed after submission. Submit a new offer instead.'
                );
            } else if (
                offer.Status__c != old.Status__c && !statusChangeAllowed
            ) {
                offer.Status__c.addError(
                    'Offer status can only be changed with the Approve, Accept and Reject actions.'
                );
            }
        }
    }

    private static Boolean isOpenForOffers(Property__c property) {
        return property.Status__c != PROPERTY_STATUS_CLOSED &&
            property.Status__c != PROPERTY_STATUS_UNDER_AGREEMENT;
    }

    public static Offer__c approve(Id offerId) {
        if (!FeatureManagement.checkPermission('Approve_Offers')) {
            throw new OfferException(
                'Only brokers with the Approve Offers permission can approve offers.'
            );
        }
        Offer__c offer = getOffer(offerId);
        if (offer.Status__c != STATUS_NEEDS_APPROVAL) {
            throw new OfferException(
                'Only offers that need approval can be approved.'
            );
        }
        return updateStatus(offer, STATUS_APPROVED);
    }

    /**
     * Accepts an offer, rejects the other open offers and puts the property under agreement.
     */
    public static Offer__c accept(Id offerId) {
        Offer__c offer = getOffer(offerId);
        if (offer.Status__c == STATUS_NEEDS_APPROVAL) {
            throw new OfferException(
                'This offer is more than ' +
                    APPROVAL_THRESHOLD_PERCENT.format() +
                    '% below asking and needs broker approval before it can be accepted.'
            );
        }
        if (
            offer.Status__c != STATUS_SUBMITTED &&
            offer.Status__c != STATUS_APPROVED
        ) {
            throw new OfferException(
                'Only submitted or approved offers can be accepted.'
            );
        }

        Property__c property = [
            SELECT Id, Status__c
            FROM Property__c
            WHERE Id = :offer.Property__c
            WITH SYSTEM_MODE
            FOR UPDATE
        ];
        if (!isOpenForOffers(property)) {
            throw new OfferException(
                'Offers cannot be accepted on a property that is ' +
                    property.Status__c +
                    '.'
            );
        }

        List<Offer__c> toUpdate = new List<Offer__c>{
            new Offer__c(Id = offer.Id, Status__c = STATUS_ACCEPTED)
        };
        for (Offer__c other : [
            SELECT Id, Status__c
            FROM Offer__c
            WHERE
                Property__c = :offer.Property__c
                AND Id != :offer.Id
                AND Status__c IN (
                    :STATUS_SUBMITTED,
                    :STATUS_NEEDS_APPROVAL,
                    :STATUS_APPROVED
                )
            WITH USER_MODE
        ]) {
            toUpdate.add(
                new Offer__c(Id = other.Id, Status__c = STATUS_REJECTED)
            );
        }
        updateStatuses(toUpdate);

        update as user new Property__c(
            Id = offer.Property__c,
            Status__c = PROPERTY_STATUS_UNDER_AGREEMENT,
            Date_Agreement__c = Date.today()
        );
        offer.Status__c = STATUS_ACCEPTED;
        return offer;
    }

    public static Offer__c reject(Id offerId) {
        Offer__c offer = getOffer(offerId);
        if (
            offer.Status__c == STATUS_ACCEPTED ||
            offer.Status__c == STATUS_REJECTED
        ) {
            throw new OfferException('This offer is already closed.');
        }
        return updateStatus(offer, STATUS_REJECTED);
    }

    // Master-detail fields aren't updateable, so update only the status.
    private static Offer__c updateStatus(Offer__c offer, String status) {
        updateStatuses(
            new List<Offer__c>{
                new Offer__c(Id = offer.Id, Status__c = status)
            }
        );
        offer.Status__c = status;
        return offer;
    }

    private static void updateStatuses(List<Offer__c> offers) {
        statusChangeAllowed = true;
        try {
            update as user offers;
        } finally {
            statusChangeAllowed = false;
        }
    }

    private static Offer__c getOffer(Id offerId) {
        List<Offer__c> offers = [
            SELECT Id, Property__c, Status__c
            FROM Offer__c
            WHERE Id = :offerId
            WITH USER_MODE
        ];
        if (offers.isEmpty()) {
            throw new OfferException('Offer not found.');
        }
        return offers[0];
    }
}
