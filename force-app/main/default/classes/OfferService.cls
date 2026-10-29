/**
 * Business rules for buyer offers on a property.
 *
 * Offers more than APPROVAL_THRESHOLD percent below asking are created as
 * Needs Approval and must be approved by a user with the Approve_Offers
 * custom permission before they can be accepted. Status changes are only
 * allowed through this service; OfferTrigger enforces that.
 */
public with sharing class OfferService {
    public static final Decimal APPROVAL_THRESHOLD = 10;
    public static final String APPROVE_PERMISSION = 'Approve_Offers';

    public static final String STATUS_SUBMITTED = 'Submitted';
    public static final String STATUS_NEEDS_APPROVAL = 'Needs Approval';
    public static final String STATUS_APPROVED = 'Approved';
    public static final String STATUS_ACCEPTED = 'Accepted';
    public static final String STATUS_REJECTED = 'Rejected';

    public static final String PROPERTY_UNDER_AGREEMENT = 'Under Agreement';
    public static final Set<String> CLOSED_PROPERTY_STATUSES = new Set<String>{
        'Closed',
        'Contracted',
        PROPERTY_UNDER_AGREEMENT
    };
    public static final Set<String> OPEN_OFFER_STATUSES = new Set<String>{
        STATUS_SUBMITTED,
        STATUS_NEEDS_APPROVAL,
        STATUS_APPROVED
    };

    private static final Map<String, Set<String>> ALLOWED_TRANSITIONS = new Map<String, Set<String>>{
        STATUS_SUBMITTED => new Set<String>{ STATUS_ACCEPTED, STATUS_REJECTED },
        STATUS_NEEDS_APPROVAL => new Set<String>{
            STATUS_APPROVED,
            STATUS_REJECTED
        },
        STATUS_APPROVED => new Set<String>{ STATUS_ACCEPTED, STATUS_REJECTED }
    };

    @TestVisible
    private static Boolean serviceDmlInProgress = false;

    public class OfferException extends Exception {
    }

    /**
     * Percent the amount is below the asking price, rounded half-up to one
     * decimal place. Negative when the offer is above asking.
     */
    public static Decimal percentBelowAsking(
        Decimal askingPrice,
        Decimal amount
    ) {
        if (askingPrice == null || askingPrice <= 0) {
            throw new OfferException('This property has no asking price.');
        }
        return ((askingPrice - amount) * 100)
            .divide(askingPrice, 1, System.RoundingMode.HALF_UP);
    }

    public static Boolean needsApproval(Decimal percentBelow) {
        return percentBelow > APPROVAL_THRESHOLD;
    }

    public static Boolean canApprove() {
        return FeatureManagement.checkPermission(APPROVE_PERMISSION);
    }

    public static Offer__c submitOffer(
        Id propertyId,
        String buyerName,
        Decimal amount
    ) {
        if (String.isBlank(buyerName)) {
            throw new OfferException('Enter the buyer name.');
        }
        if (amount == null || amount <= 0) {
            throw new OfferException('Offer amount must be greater than zero.');
        }
        Property__c property = lockProperty(propertyId);
        assertPropertyOpen(property);

        Decimal percentBelow = percentBelowAsking(property.Price__c, amount);
        Offer__c offer = new Offer__c(
            Property__c = propertyId,
            Buyer_Name__c = buyerName.trim(),
            Amount__c = amount,
            Percent_Below_Asking__c = percentBelow,
            Status__c = needsApproval(percentBelow)
                ? STATUS_NEEDS_APPROVAL
                : STATUS_SUBMITTED
        );
        runServiceDml(new List<SObject>{ offer }, true);
        return offer;
    }

    public static Offer__c approveOffer(Id offerId) {
        if (!canApprove()) {
            throw new OfferException(
                'Only brokers with the Approve Offers permission can approve offers.'
            );
        }
        Offer__c offer = lockOfferAndProperty(offerId);
        if (offer.Status__c != STATUS_NEEDS_APPROVAL) {
            throw new OfferException(
                'Only offers that need approval can be approved.'
            );
        }
        return setStatus(offer, STATUS_APPROVED);
    }

    public static Offer__c rejectOffer(Id offerId) {
        Offer__c offer = lockOfferAndProperty(offerId);
        if (!OPEN_OFFER_STATUSES.contains(offer.Status__c)) {
            throw new OfferException('This offer is already closed.');
        }
        return setStatus(offer, STATUS_REJECTED);
    }

    /**
     * Accepts an offer: rejects the property's other open offers and puts
     * the property Under Agreement.
     */
    public static Offer__c acceptOffer(Id offerId) {
        Offer__c offer = lockOfferAndProperty(offerId);
        Property__c property = lockedProperty;
        assertPropertyOpen(property);

        if (offer.Status__c == STATUS_NEEDS_APPROVAL) {
            throw new OfferException(
                'This offer needs broker approval before it can be accepted.'
            );
        }
        if (
            offer.Status__c != STATUS_SUBMITTED &&
            offer.Status__c != STATUS_APPROVED
        ) {
            throw new OfferException('This offer is already closed.');
        }
        if (offer.Status__c == STATUS_SUBMITTED) {
            Decimal currentPercent = percentBelowAsking(
                property.Price__c,
                offer.Amount__c
            );
            if (needsApproval(currentPercent)) {
                throw new OfferException(
                    'The asking price has changed. This offer is now ' +
                        currentPercent +
                        '% below asking and needs broker approval.'
                );
            }
        }

        List<SObject> updates = new List<SObject>{
            new Offer__c(Id = offer.Id, Status__c = STATUS_ACCEPTED)
        };
        for (Offer__c other : [
            SELECT Id
            FROM Offer__c
            WHERE
                Property__c = :property.Id
                AND Id != :offer.Id
                AND Status__c IN :OPEN_OFFER_STATUSES
            WITH USER_MODE
            FOR UPDATE
        ]) {
            updates.add(
                new Offer__c(Id = other.Id, Status__c = STATUS_REJECTED)
            );
        }
        runServiceDml(updates, false);

        update as user new Property__c(
            Id = property.Id,
            Status__c = PROPERTY_UNDER_AGREEMENT,
            Date_Agreement__c = Date.today()
        );
        return new Offer__c(
            Id = offer.Id,
            Property__c = property.Id,
            Buyer_Name__c = offer.Buyer_Name__c,
            Amount__c = offer.Amount__c,
            Percent_Below_Asking__c = offer.Percent_Below_Asking__c,
            Status__c = STATUS_ACCEPTED
        );
    }

    public static void validateBeforeInsert(List<Offer__c> newOffers) {
        if (serviceDmlInProgress) {
            return;
        }
        for (Offer__c offer : newOffers) {
            offer.addError(
                'Offers must be submitted from the Offers card on the property.'
            );
        }
    }

    public static void validateBeforeUpdate(
        List<Offer__c> newOffers,
        Map<Id, Offer__c> oldOffers
    ) {
        for (Offer__c offer : newOffers) {
            Offer__c old = oldOffers.get(offer.Id);
            if (offer.Property__c != old.Property__c) {
                offer.Property__c.addError(
                    'An offer cannot be moved to another property.'
                );
            }
            if (offer.Amount__c != old.Amount__c) {
                offer.Amount__c.addError(
                    'Offer amount cannot be changed after submission.'
                );
            }
            if (offer.Percent_Below_Asking__c != old.Percent_Below_Asking__c) {
                offer.Percent_Below_Asking__c.addError(
                    '% Below Asking cannot be changed after submission.'
                );
            }
            if (offer.Status__c == old.Status__c) {
                continue;
            }
            Set<String> allowed = ALLOWED_TRANSITIONS.get(old.Status__c);
            if (!serviceDmlInProgress) {
                offer.Status__c.addError(
                    'Use Approve, Accept or Reject on the Offers card to change an offer status.'
                );
            } else if (allowed == null || !allowed.contains(offer.Status__c)) {
                offer.Status__c.addError(
                    'An offer cannot move from ' +
                        old.Status__c +
                        ' to ' +
                        offer.Status__c +
                        '.'
                );
            }
        }
    }

    private static Property__c lockedProperty;

    private static Property__c lockProperty(Id propertyId) {
        List<Property__c> properties = [
            SELECT Id, Name, Price__c, Status__c
            FROM Property__c
            WHERE Id = :propertyId
            WITH USER_MODE
            FOR UPDATE
        ];
        if (properties.isEmpty()) {
            throw new OfferException('Property not found.');
        }
        lockedProperty = properties[0];
        return lockedProperty;
    }

    // Locks the parent property first, then the offer, so concurrent
    // approve/accept/reject calls on the same property serialize.
    private static Offer__c lockOfferAndProperty(Id offerId) {
        List<Offer__c> found = [
            SELECT Property__c
            FROM Offer__c
            WHERE Id = :offerId
            WITH USER_MODE
        ];
        if (found.isEmpty()) {
            throw new OfferException('Offer not found.');
        }
        lockProperty(found[0].Property__c);
        return [
            SELECT
                Id,
                Property__c,
                Buyer_Name__c,
                Amount__c,
                Percent_Below_Asking__c,
                Status__c
            FROM Offer__c
            WHERE Id = :offerId
            WITH USER_MODE
            FOR UPDATE
        ];
    }

    private static void assertPropertyOpen(Property__c property) {
        if (CLOSED_PROPERTY_STATUSES.contains(property.Status__c)) {
            throw new OfferException(
                'This property is ' +
                    property.Status__c +
                    ' and is no longer taking offers.'
            );
        }
    }

    private static Offer__c setStatus(Offer__c offer, String status) {
        runServiceDml(
            new List<SObject>{
                new Offer__c(Id = offer.Id, Status__c = status)
            },
            false
        );
        offer.Status__c = status;
        return offer;
    }

    private static void runServiceDml(List<SObject> records, Boolean isInsert) {
        serviceDmlInProgress = true;
        try {
            if (isInsert) {
                insert as user records;
            } else {
                update as user records;
            }
        } finally {
            serviceDmlInProgress = false;
        }
    }
}
