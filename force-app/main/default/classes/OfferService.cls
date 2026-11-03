/**
 * Business rules for buyer offers on Dreamhouse properties.
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

    public static final Set<String> OPEN_STATUSES = new Set<String>{
        STATUS_SUBMITTED,
        STATUS_NEEDS_APPROVAL,
        STATUS_APPROVED
    };
    public static final Set<String> CLOSED_PROPERTY_STATUSES = new Set<String>{
        'Under Agreement',
        'Contracted',
        'Closed'
    };

    private static final Map<String, Set<String>> ALLOWED_TRANSITIONS = new Map<String, Set<String>>{
        STATUS_SUBMITTED => new Set<String>{
            STATUS_APPROVED,
            STATUS_ACCEPTED,
            STATUS_REJECTED
        },
        STATUS_NEEDS_APPROVAL => new Set<String>{
            STATUS_APPROVED,
            STATUS_REJECTED
        },
        STATUS_APPROVED => new Set<String>{
            STATUS_APPROVED,
            STATUS_ACCEPTED,
            STATUS_REJECTED
        }
    };

    /** Exact status writes the service is about to make, keyed by offer Id. */
    private static Map<Id, Offer__c> pendingWrites = new Map<Id, Offer__c>();

    public class OfferException extends Exception {
    }

    public static Decimal percentBelowAsking(
        Decimal askingPrice,
        Decimal amount
    ) {
        return ((askingPrice - amount) /
            askingPrice *
            100)
            .setScale(1, RoundingMode.HALF_UP);
    }

    /**
     * The larger of the discount at submission and the discount at the current
     * asking price, so lowering the price cannot bypass broker approval.
     */
    public static Decimal effectivePercentBelow(
        Offer__c offer,
        Decimal askingPrice
    ) {
        Decimal current = percentBelowAsking(askingPrice, offer.Amount__c);
        return offer.Percent_Below_Asking__c == null
            ? current
            : Math.max(current, offer.Percent_Below_Asking__c);
    }

    public static Boolean requiresApproval(
        Offer__c offer,
        Decimal askingPrice
    ) {
        Decimal current = effectivePercentBelow(offer, askingPrice);
        if (current <= APPROVAL_THRESHOLD) {
            return false;
        }
        return offer.Approved_Percent_Below__c == null ||
            current > offer.Approved_Percent_Below__c;
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
            throw new OfferException('Enter a buyer name.');
        }
        if (amount == null || amount <= 0) {
            throw new OfferException('Offer amount must be greater than zero.');
        }
        Property__c property = getProperty(propertyId, false);
        assertPropertyOpen(property);

        Decimal percentBelow = percentBelowAsking(property.Price__c, amount);
        Offer__c offer = new Offer__c(
            Property__c = property.Id,
            Buyer_Name__c = buyerName.trim(),
            Amount__c = amount,
            Percent_Below_Asking__c = percentBelow,
            Status__c = percentBelow > APPROVAL_THRESHOLD
                ? STATUS_NEEDS_APPROVAL
                : STATUS_SUBMITTED
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
        Property__c property = lockPropertyForOffer(offerId);
        assertPropertyOpen(property);
        Offer__c offer = lockOffer(offerId);
        Boolean needsApproval = requiresApproval(offer, property.Price__c);
        if (
            offer.Status__c != STATUS_NEEDS_APPROVAL &&
            !(OPEN_STATUSES.contains(offer.Status__c) && needsApproval)
        ) {
            throw new OfferException(
                'Only offers that need approval can be approved.'
            );
        }
        writeOffers(
            new List<Offer__c>{
                new Offer__c(
                    Id = offer.Id,
                    Status__c = STATUS_APPROVED,
                    Approved_Percent_Below__c = effectivePercentBelow(
                        offer,
                        property.Price__c
                    )
                )
            }
        );
    }

    public static void acceptOffer(Id offerId) {
        Property__c property = lockPropertyForOffer(offerId);
        assertPropertyOpen(property);
        Offer__c offer = lockOffer(offerId);
        if (
            offer.Status__c != STATUS_SUBMITTED &&
            offer.Status__c != STATUS_APPROVED
        ) {
            throw new OfferException(
                offer.Status__c == STATUS_NEEDS_APPROVAL
                    ? 'This offer needs broker approval before it can be accepted.'
                    : 'Only submitted or approved offers can be accepted.'
            );
        }
        if (requiresApproval(offer, property.Price__c)) {
            throw new OfferException(
                'This offer needs broker approval at the current asking price before it can be accepted.'
            );
        }
        List<Offer__c> siblings = [
            SELECT Id, Status__c
            FROM Offer__c
            WHERE Property__c = :property.Id AND Id != :offer.Id
            WITH USER_MODE
            FOR UPDATE
        ];
        List<Offer__c> writes = new List<Offer__c>{
            new Offer__c(Id = offer.Id, Status__c = STATUS_ACCEPTED)
        };
        for (Offer__c other : siblings) {
            if (other.Status__c == STATUS_ACCEPTED) {
                throw new OfferException(
                    'This property already has an accepted offer.'
                );
            }
            if (OPEN_STATUSES.contains(other.Status__c)) {
                writes.add(
                    new Offer__c(Id = other.Id, Status__c = STATUS_REJECTED)
                );
            }
        }
        writeOffers(writes);
        update as user new Property__c(
            Id = property.Id,
            Status__c = 'Under Agreement',
            Date_Agreement__c = Date.today()
        );
    }

    public static void rejectOffer(Id offerId) {
        Property__c property = lockPropertyForOffer(offerId);
        assertPropertyOpen(property);
        Offer__c offer = lockOffer(offerId);
        if (!OPEN_STATUSES.contains(offer.Status__c)) {
            throw new OfferException('Only open offers can be rejected.');
        }
        writeOffers(
            new List<Offer__c>{
                new Offer__c(Id = offer.Id, Status__c = STATUS_REJECTED)
            }
        );
    }

    /** Before-insert trigger guard: derived fields always match the asking price. */
    public static void enforceOnInsert(List<Offer__c> offers) {
        Set<Id> propertyIds = new Set<Id>();
        for (Offer__c offer : offers) {
            propertyIds.add(offer.Property__c);
        }
        Map<Id, Property__c> properties = new Map<Id, Property__c>(
            [
                SELECT Id, Price__c, Status__c
                FROM Property__c
                WHERE Id IN :propertyIds
                WITH USER_MODE
            ]
        );
        for (Offer__c offer : offers) {
            Property__c property = properties.get(offer.Property__c);
            if (offer.Amount__c == null || offer.Amount__c <= 0) {
                offer.addError('Offer amount must be greater than zero.');
            } else if (
                property == null ||
                property.Price__c == null ||
                property.Price__c <= 0
            ) {
                offer.addError('The property has no asking price.');
            } else if (CLOSED_PROPERTY_STATUSES.contains(property.Status__c)) {
                offer.addError(closedMessage(property));
            } else {
                Decimal percentBelow = percentBelowAsking(
                    property.Price__c,
                    offer.Amount__c
                );
                offer.Percent_Below_Asking__c = percentBelow;
                offer.Approved_Percent_Below__c = null;
                offer.Status__c = percentBelow > APPROVAL_THRESHOLD
                    ? STATUS_NEEDS_APPROVAL
                    : STATUS_SUBMITTED;
            }
        }
    }

    /** Before-update trigger guard: amounts are immutable, status moves only via this service. */
    public static void enforceOnUpdate(
        List<Offer__c> offers,
        Map<Id, Offer__c> oldOffers
    ) {
        for (Offer__c offer : offers) {
            Offer__c old = oldOffers.get(offer.Id);
            if (
                offer.Amount__c != old.Amount__c ||
                offer.Percent_Below_Asking__c != old.Percent_Below_Asking__c ||
                offer.Property__c != old.Property__c ||
                offer.Buyer_Name__c != old.Buyer_Name__c
            ) {
                offer.addError(
                    'An offer cannot be changed after it is submitted.'
                );
                continue;
            }
            Boolean statusChanged = offer.Status__c != old.Status__c;
            Boolean approvalChanged =
                offer.Approved_Percent_Below__c !=
                old.Approved_Percent_Below__c;
            if (!statusChanged && !approvalChanged) {
                continue;
            }
            Offer__c expected = pendingWrites.get(offer.Id);
            Set<String> allowedNext = ALLOWED_TRANSITIONS.get(old.Status__c);
            Boolean matchesWrite =
                expected != null &&
                expected.Status__c == offer.Status__c &&
                (expected.Approved_Percent_Below__c == null ||
                expected.Approved_Percent_Below__c ==
                offer.Approved_Percent_Below__c) &&
                (expected.Approved_Percent_Below__c != null ||
                !approvalChanged);
            if (
                !matchesWrite ||
                allowedNext == null ||
                !allowedNext.contains(offer.Status__c)
            ) {
                offer.addError(
                    'Offer status can only be changed with Approve, Accept or Reject.'
                );
            }
        }
    }

    /** Throws unless the offer belongs to the given property. */
    public static void assertOfferOnProperty(Id propertyId, Id offerId) {
        List<Offer__c> offers = [
            SELECT Id
            FROM Offer__c
            WHERE Id = :offerId AND Property__c = :propertyId
            WITH USER_MODE
        ];
        if (offers.isEmpty()) {
            throw new OfferException('Offer not found on this property.');
        }
    }

    private static void writeOffers(List<Offer__c> writes) {
        for (Offer__c write : writes) {
            pendingWrites.put(write.Id, write);
        }
        try {
            update as user writes;
        } finally {
            for (Offer__c write : writes) {
                pendingWrites.remove(write.Id);
            }
        }
    }

    private static Property__c lockPropertyForOffer(Id offerId) {
        List<Offer__c> offers = [
            SELECT Property__c
            FROM Offer__c
            WHERE Id = :offerId
            WITH USER_MODE
        ];
        if (offers.isEmpty()) {
            throw new OfferException('Offer not found.');
        }
        return getProperty(offers[0].Property__c, true);
    }

    private static Offer__c lockOffer(Id offerId) {
        return [
            SELECT
                Id,
                Property__c,
                Amount__c,
                Percent_Below_Asking__c,
                Approved_Percent_Below__c,
                Status__c
            FROM Offer__c
            WHERE Id = :offerId
            WITH USER_MODE
            FOR UPDATE
        ];
    }

    private static Property__c getProperty(Id propertyId, Boolean lockRow) {
        List<Property__c> properties = lockRow
            ? [
                  SELECT Id, Name, Price__c, Status__c
                  FROM Property__c
                  WHERE Id = :propertyId
                  WITH USER_MODE
                  FOR UPDATE
              ]
            : [
                  SELECT Id, Name, Price__c, Status__c
                  FROM Property__c
                  WHERE Id = :propertyId
                  WITH USER_MODE
              ];
        if (properties.isEmpty()) {
            throw new OfferException('Property not found.');
        }
        if (properties[0].Price__c == null || properties[0].Price__c <= 0) {
            throw new OfferException('The property has no asking price.');
        }
        return properties[0];
    }

    private static void assertPropertyOpen(Property__c property) {
        if (CLOSED_PROPERTY_STATUSES.contains(property.Status__c)) {
            throw new OfferException(closedMessage(property));
        }
    }

    private static String closedMessage(Property__c property) {
        return 'Offers are closed: the property is ' + property.Status__c + '.';
    }
}
