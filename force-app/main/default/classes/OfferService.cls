/**
 * Offers on a property with discount approval.
 * Offers more than APPROVAL_THRESHOLD percent below asking need a broker with
 * the Approve_Offers custom permission to approve them before they can be accepted.
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
    public static final String PROPERTY_CLOSED = 'Closed';

    private static final Set<String> OPEN_STATUSES = new Set<String>{
        STATUS_SUBMITTED,
        STATUS_NEEDS_APPROVAL,
        STATUS_APPROVED
    };
    private static final Set<String> ACCEPTABLE_STATUSES = new Set<String>{
        STATUS_SUBMITTED,
        STATUS_APPROVED
    };
    private static final Set<String> LOCKED_PROPERTY_STATUSES = new Set<String>{
        PROPERTY_UNDER_AGREEMENT,
        PROPERTY_CLOSED
    };

    // Set only while submit/approve/accept/reject write offers; the trigger rejects other writes.
    private static Boolean serviceWrite = false;

    public class OfferException extends Exception {
    }

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
            .setScale(1, System.RoundingMode.HALF_UP);
    }

    public static Boolean needsApproval(Decimal percentBelowAsking) {
        return percentBelowAsking != null &&
            percentBelowAsking > APPROVAL_THRESHOLD;
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

    public static Offer__c submit(
        Id propertyId,
        String buyerName,
        Decimal amount
    ) {
        if (String.isBlank(buyerName)) {
            throw new OfferException('Enter the buyer name.');
        }
        if (amount == null || amount <= 0) {
            throw new OfferException('The offer amount must be more than $0.');
        }
        List<Property__c> properties = [
            SELECT Id, Price__c, Status__c
            FROM Property__c
            WHERE Id = :propertyId
            WITH USER_MODE
            LIMIT 1
        ];
        if (properties.isEmpty()) {
            throw new OfferException('Property not found.');
        }
        Property__c property = properties[0];
        assertOpenForOffers(property);
        if (property.Price__c == null || property.Price__c <= 0) {
            throw new OfferException(
                'This property has no asking price, so it cannot take offers.'
            );
        }

        Decimal percent = percentBelowAsking(property.Price__c, amount);
        Offer__c offer = new Offer__c(
            Property__c = property.Id,
            Buyer_Name__c = buyerName.trim(),
            Amount__c = amount,
            Percent_Below_Asking__c = percent,
            Status__c = needsApproval(percent)
                ? STATUS_NEEDS_APPROVAL
                : STATUS_SUBMITTED
        );
        serviceWrite = true;
        try {
            insert as user offer;
        } finally {
            serviceWrite = false;
        }
        return offer;
    }

    public static void approve(Id offerId) {
        if (!canApprove()) {
            throw new OfferException(
                'Only brokers with the Approve Offers permission can approve offers.'
            );
        }
        Offer__c offer = lockOffer(offerId);
        if (offer.Status__c != STATUS_NEEDS_APPROVAL) {
            throw new OfferException(
                'Only offers that need approval can be approved.'
            );
        }
        writeStatuses(
            new List<Offer__c>{
                new Offer__c(Id = offer.Id, Status__c = STATUS_APPROVED)
            }
        );
    }

    public static void accept(Id offerId) {
        Offer__c target = lockOffer(offerId);
        Property__c property = [
            SELECT Id, Status__c
            FROM Property__c
            WHERE Id = :target.Property__c
            WITH USER_MODE
            FOR UPDATE
        ];
        assertOpenForOffers(property);

        // Re-read under the property lock so a concurrent approve/reject is seen.
        List<Offer__c> offers = [
            SELECT Id, Status__c
            FROM Offer__c
            WHERE Property__c = :property.Id
            WITH USER_MODE
            FOR UPDATE
        ];
        List<Offer__c> updates = new List<Offer__c>();
        for (Offer__c offer : offers) {
            if (offer.Id == offerId) {
                if (offer.Status__c == STATUS_NEEDS_APPROVAL) {
                    throw new OfferException(
                        'This offer is more than 10% below asking. A broker must approve it before it can be accepted.'
                    );
                }
                if (!ACCEPTABLE_STATUSES.contains(offer.Status__c)) {
                    throw new OfferException(
                        'Only submitted or approved offers can be accepted.'
                    );
                }
                updates.add(
                    new Offer__c(Id = offer.Id, Status__c = STATUS_ACCEPTED)
                );
            } else if (OPEN_STATUSES.contains(offer.Status__c)) {
                updates.add(
                    new Offer__c(Id = offer.Id, Status__c = STATUS_REJECTED)
                );
            }
        }
        writeStatuses(updates);
        update as user new Property__c(
            Id = property.Id,
            Status__c = PROPERTY_UNDER_AGREEMENT,
            Date_Agreement__c = Date.today()
        );
    }

    public static void reject(Id offerId) {
        Offer__c offer = lockOffer(offerId);
        if (!OPEN_STATUSES.contains(offer.Status__c)) {
            throw new OfferException('Only open offers can be rejected.');
        }
        writeStatuses(
            new List<Offer__c>{
                new Offer__c(Id = offer.Id, Status__c = STATUS_REJECTED)
            }
        );
    }

    public static void guardInsert(List<Offer__c> offers) {
        if (serviceWrite) {
            return;
        }
        for (Offer__c offer : offers) {
            offer.addError(
                'Offers must be submitted from the Offers card so the discount check runs.'
            );
        }
    }

    public static void guardUpdate(
        List<Offer__c> offers,
        Map<Id, Offer__c> oldOffers
    ) {
        for (Offer__c offer : offers) {
            Offer__c old = oldOffers.get(offer.Id);
            if (
                offer.Amount__c != old.Amount__c ||
                offer.Percent_Below_Asking__c != old.Percent_Below_Asking__c
            ) {
                offer.addError(
                    'The offer amount and % below asking cannot be changed after submission.'
                );
            } else if (offer.Status__c != old.Status__c && !serviceWrite) {
                offer.addError(
                    'Offer status can only be changed with Approve, Accept or Reject.'
                );
            }
        }
    }

    private static void assertOpenForOffers(Property__c property) {
        if (LOCKED_PROPERTY_STATUSES.contains(property.Status__c)) {
            throw new OfferException(
                'This property is ' +
                    property.Status__c +
                    ' and is not taking offers.'
            );
        }
    }

    private static Offer__c lockOffer(Id offerId) {
        List<Offer__c> offers = [
            SELECT Id, Status__c, Property__c
            FROM Offer__c
            WHERE Id = :offerId
            WITH USER_MODE
            LIMIT 1
            FOR UPDATE
        ];
        if (offers.isEmpty()) {
            throw new OfferException('Offer not found.');
        }
        return offers[0];
    }

    private static void writeStatuses(List<Offer__c> offers) {
        serviceWrite = true;
        try {
            update as user offers;
        } finally {
            serviceWrite = false;
        }
    }
}
