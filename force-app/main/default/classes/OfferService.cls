/**
 * Business rules for buyer offers on a property, including discount approval:
 * offers more than 10% below asking need a broker with the Approve_Offers
 * custom permission to approve them before they can be accepted.
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

    public static final Set<String> OPEN_STATUSES = new Set<String>{
        STATUS_SUBMITTED,
        STATUS_NEEDS_APPROVAL,
        STATUS_APPROVED
    };

    public static final Set<String> CLOSED_PROPERTY_STATUSES = new Set<String>{
        PROPERTY_UNDER_AGREEMENT,
        'Contracted',
        'Closed'
    };

    private static final Map<String, Set<String>> ALLOWED_TRANSITIONS = new Map<String, Set<String>>{
        STATUS_SUBMITTED => new Set<String>{ STATUS_ACCEPTED, STATUS_REJECTED },
        STATUS_NEEDS_APPROVAL => new Set<String>{
            STATUS_APPROVED,
            STATUS_REJECTED
        },
        STATUS_APPROVED => new Set<String>{ STATUS_ACCEPTED, STATUS_REJECTED },
        STATUS_ACCEPTED => new Set<String>(),
        STATUS_REJECTED => new Set<String>()
    };

    // Set only while approve/accept/reject run their own DML, so the trigger
    // can refuse status changes made any other way.
    private static Boolean statusChangeInProgress = false;

    public class OfferException extends Exception {
    }

    private class LockedOffer {
        Property__c property;
        Offer__c offer;
    }

    /**
     * Percentage below asking, rounded half-up to one decimal place.
     * Negative when the offer is above asking.
     */
    public static Decimal percentBelowAsking(
        Decimal askingPrice,
        Decimal amount
    ) {
        if (askingPrice == null || askingPrice <= 0 || amount == null) {
            return null;
        }
        return ((askingPrice - amount) /
            askingPrice *
            100)
            .setScale(1, RoundingMode.HALF_UP);
    }

    public static String initialStatus(Decimal percentBelowAsking) {
        return percentBelowAsking != null &&
            percentBelowAsking > APPROVAL_THRESHOLD
            ? STATUS_NEEDS_APPROVAL
            : STATUS_SUBMITTED;
    }

    public static Boolean canApprove() {
        return FeatureManagement.checkPermission(APPROVE_PERMISSION);
    }

    public static List<Offer__c> getOffers(Id propertyId) {
        return [
            SELECT
                Id,
                Name,
                Buyer_Name__c,
                Amount__c,
                Percent_Below_Asking__c,
                Status__c,
                CreatedDate
            FROM Offer__c
            WHERE Property__c = :propertyId
            WITH USER_MODE
            ORDER BY CreatedDate DESC, Name DESC
        ];
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
        List<Property__c> properties = [
            SELECT Id, Price__c, Status__c
            FROM Property__c
            WHERE Id = :propertyId
            WITH USER_MODE
        ];
        if (properties.isEmpty()) {
            throw new OfferException('Property not found.');
        }
        Property__c property = properties[0];
        assertPropertyOpen(property);
        if (property.Price__c == null || property.Price__c <= 0) {
            throw new OfferException(
                'This property has no asking price, so offers cannot be submitted.'
            );
        }

        Decimal percent = percentBelowAsking(property.Price__c, amount);
        Offer__c offer = new Offer__c(
            Property__c = property.Id,
            Buyer_Name__c = buyerName.trim(),
            Amount__c = amount,
            Percent_Below_Asking__c = percent,
            Status__c = initialStatus(percent)
        );
        insert as user offer;
        return offer;
    }

    public static void approveOffer(Id offerId) {
        if (!canApprove()) {
            throw new OfferException(
                'Only brokers with the Approve Offers permission can approve offers.'
            );
        }
        LockedOffer locked = lockOffer(offerId);
        assertPropertyOpen(locked.property);
        if (locked.offer.Status__c != STATUS_NEEDS_APPROVAL) {
            throw new OfferException(
                'Only offers that need approval can be approved.'
            );
        }
        updateStatuses(
            new List<Offer__c>{
                new Offer__c(Id = offerId, Status__c = STATUS_APPROVED)
            }
        );
    }

    public static void rejectOffer(Id offerId) {
        LockedOffer locked = lockOffer(offerId);
        if (!OPEN_STATUSES.contains(locked.offer.Status__c)) {
            throw new OfferException('Only open offers can be rejected.');
        }
        updateStatuses(
            new List<Offer__c>{
                new Offer__c(Id = offerId, Status__c = STATUS_REJECTED)
            }
        );
    }

    /**
     * Accepts the offer, rejects every other open offer on the property and
     * puts the property Under Agreement.
     */
    public static void acceptOffer(Id offerId) {
        LockedOffer locked = lockOffer(offerId);
        assertPropertyOpen(locked.property);
        if (locked.offer.Status__c == STATUS_NEEDS_APPROVAL) {
            throw new OfferException(
                'This offer is more than 10% below asking and needs broker approval before it can be accepted.'
            );
        }
        if (
            locked.offer.Status__c != STATUS_SUBMITTED &&
            locked.offer.Status__c != STATUS_APPROVED
        ) {
            throw new OfferException(
                'Only submitted or approved offers can be accepted.'
            );
        }
        // The asking price may have changed since submission; re-check the
        // discount so a price edit can't skip broker approval.
        if (
            locked.offer.Status__c == STATUS_SUBMITTED &&
            initialStatus(
                percentBelowAsking(
                    locked.property.Price__c,
                    locked.offer.Amount__c
                )
            ) == STATUS_NEEDS_APPROVAL
        ) {
            throw new OfferException(
                'The asking price has changed since this offer was submitted and it is now more than 10% below asking. Reject it and submit a new offer for broker approval.'
            );
        }

        List<Offer__c> updates = new List<Offer__c>{
            new Offer__c(Id = offerId, Status__c = STATUS_ACCEPTED)
        };
        for (Offer__c other : [
            SELECT Id
            FROM Offer__c
            WHERE
                Property__c = :locked.property.Id
                AND Id != :offerId
                AND Status__c IN :OPEN_STATUSES
            WITH USER_MODE
            FOR UPDATE
        ]) {
            updates.add(
                new Offer__c(Id = other.Id, Status__c = STATUS_REJECTED)
            );
        }
        updateStatuses(updates);

        update as user new Property__c(
            Id = locked.property.Id,
            Status__c = PROPERTY_UNDER_AGREEMENT,
            Date_Agreement__c = Date.today()
        );
    }

    /**
     * Before insert: recalculates % below asking and the starting status from
     * the property's asking price, so offers created outside the Offers card
     * can't skip approval.
     */
    public static void enforceInsertRules(List<Offer__c> offers) {
        Set<Id> propertyIds = new Set<Id>();
        for (Offer__c offer : offers) {
            propertyIds.add(offer.Property__c);
        }
        Map<Id, Property__c> properties = new Map<Id, Property__c>(
            [
                SELECT Id, Price__c, Status__c
                FROM Property__c
                WHERE Id IN :propertyIds
            ]
        );
        for (Offer__c offer : offers) {
            Property__c property = properties.get(offer.Property__c);
            if (offer.Amount__c == null || offer.Amount__c <= 0) {
                offer.Amount__c.addError(
                    'Offer amount must be greater than zero.'
                );
                continue;
            }
            if (property == null) {
                offer.addError('Property not found.');
                continue;
            }
            if (CLOSED_PROPERTY_STATUSES.contains(property.Status__c)) {
                offer.addError(closedPropertyMessage(property));
                continue;
            }
            if (property.Price__c == null || property.Price__c <= 0) {
                offer.addError(
                    'This property has no asking price, so offers cannot be submitted.'
                );
                continue;
            }
            offer.Percent_Below_Asking__c = percentBelowAsking(
                property.Price__c,
                offer.Amount__c
            );
            offer.Status__c = initialStatus(offer.Percent_Below_Asking__c);
        }
    }

    /**
     * Before update: amount and % below asking are fixed once submitted, and
     * status only moves through approve/accept/reject along allowed paths.
     */
    public static void enforceUpdateRules(
        List<Offer__c> offers,
        Map<Id, Offer__c> oldOffers
    ) {
        for (Offer__c offer : offers) {
            Offer__c old = oldOffers.get(offer.Id);
            if (offer.Amount__c != old.Amount__c) {
                offer.Amount__c.addError(
                    'Offer amount cannot be changed after the offer is submitted.'
                );
            }
            if (offer.Percent_Below_Asking__c != old.Percent_Below_Asking__c) {
                offer.Percent_Below_Asking__c.addError(
                    '% below asking is calculated when the offer is submitted and cannot be changed.'
                );
            }
            if (offer.Status__c == old.Status__c) {
                continue;
            }
            if (!statusChangeInProgress) {
                offer.Status__c.addError(
                    'Use Approve, Accept or Reject on the Offers card to change an offer\'s status.'
                );
                continue;
            }
            Set<String> allowed = ALLOWED_TRANSITIONS.get(old.Status__c);
            if (allowed == null || !allowed.contains(offer.Status__c)) {
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

    private static LockedOffer lockOffer(Id offerId) {
        List<Offer__c> found = [
            SELECT Id, Property__c
            FROM Offer__c
            WHERE Id = :offerId
            WITH USER_MODE
        ];
        if (found.isEmpty()) {
            throw new OfferException('Offer not found.');
        }
        LockedOffer locked = new LockedOffer();
        // Lock the property before the offer so concurrent accepts on the
        // same property serialize in the same order.
        locked.property = [
            SELECT Id, Name, Price__c, Status__c
            FROM Property__c
            WHERE Id = :found[0].Property__c
            WITH USER_MODE
            FOR UPDATE
        ];
        locked.offer = [
            SELECT Id, Property__c, Amount__c, Status__c
            FROM Offer__c
            WHERE Id = :offerId
            WITH USER_MODE
            FOR UPDATE
        ];
        return locked;
    }

    private static void assertPropertyOpen(Property__c property) {
        if (CLOSED_PROPERTY_STATUSES.contains(property.Status__c)) {
            throw new OfferException(closedPropertyMessage(property));
        }
    }

    private static String closedPropertyMessage(Property__c property) {
        return 'This property is ' +
            property.Status__c +
            ', so it is no longer taking offers.';
    }

    private static void updateStatuses(List<Offer__c> offers) {
        statusChangeInProgress = true;
        try {
            update as user offers;
        } finally {
            statusChangeInProgress = false;
        }
    }
}
