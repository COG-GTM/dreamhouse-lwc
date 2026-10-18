/**
 * Business rules for buyer offers on a property.
 * Offers more than APPROVAL_THRESHOLD percent below asking need a broker
 * (Approve_Offers custom permission) to approve them before they can be accepted.
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
        'Contracted',
        'Under Agreement',
        'Closed'
    };
    private static final Map<String, Set<String>> ALLOWED_TRANSITIONS = new Map<String, Set<String>>{
        STATUS_SUBMITTED => new Set<String>{ STATUS_ACCEPTED, STATUS_REJECTED },
        STATUS_NEEDS_APPROVAL => new Set<String>{
            STATUS_APPROVED,
            STATUS_REJECTED
        },
        STATUS_APPROVED => new Set<String>{ STATUS_ACCEPTED, STATUS_REJECTED }
    };

    // Set only while this class performs DML so the trigger can tell
    // approve/accept/reject transitions apart from direct status edits.
    private static Boolean statusChangeInProgress = false;

    public class OfferException extends Exception {
    }

    public static Decimal calculatePercentBelowAsking(
        Decimal askingPrice,
        Decimal amount
    ) {
        if (askingPrice == null || askingPrice <= 0 || amount == null) {
            return null;
        }
        return ((askingPrice - amount) * 100)
            .divide(askingPrice, 1, RoundingMode.HALF_UP);
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

    public static Offer__c submitOffer(
        Id propertyId,
        String buyerName,
        Decimal amount
    ) {
        Offer__c offer = new Offer__c(
            Property__c = propertyId,
            Buyer_Name__c = buyerName == null ? null : buyerName.trim(),
            Amount__c = amount
        );
        try {
            insert as user offer;
        } catch (DmlException e) {
            throw new OfferException(e.getDmlMessage(0));
        }
        return [
            SELECT
                Id,
                Name,
                Buyer_Name__c,
                Amount__c,
                Percent_Below_Asking__c,
                Status__c
            FROM Offer__c
            WHERE Id = :offer.Id
            WITH USER_MODE
        ];
    }

    public static void approveOffer(Id offerId) {
        if (!canApprove()) {
            throw new OfferException(
                'Only brokers with the Approve Offers permission can approve offers.'
            );
        }
        Offer__c offer = getOfferForUpdate(offerId);
        if (offer.Status__c != STATUS_NEEDS_APPROVAL) {
            throw new OfferException(
                'Only offers that need approval can be approved.'
            );
        }
        updateStatuses(
            new List<Offer__c>{
                new Offer__c(Id = offer.Id, Status__c = STATUS_APPROVED)
            }
        );
    }

    public static void rejectOffer(Id offerId) {
        Offer__c offer = getOfferForUpdate(offerId);
        if (!OPEN_STATUSES.contains(offer.Status__c)) {
            throw new OfferException('Only open offers can be rejected.');
        }
        updateStatuses(
            new List<Offer__c>{
                new Offer__c(Id = offer.Id, Status__c = STATUS_REJECTED)
            }
        );
    }

    public static void acceptOffer(Id offerId) {
        // Lock the property, then the offer (always in that order), so two
        // offers can't be accepted at once and the status checks aren't stale.
        Id propertyId = getOffer(offerId).Property__c;
        Property__c property = [
            SELECT Id, Status__c
            FROM Property__c
            WHERE Id = :propertyId
            WITH USER_MODE
            FOR UPDATE
        ];
        Offer__c offer = getOfferForUpdate(offerId);
        if (offer.Status__c == STATUS_NEEDS_APPROVAL) {
            throw new OfferException(
                'This offer is more than ' +
                    APPROVAL_THRESHOLD +
                    '% below asking and must be approved by a broker before it can be accepted.'
            );
        }
        if (
            offer.Status__c != STATUS_SUBMITTED &&
            offer.Status__c != STATUS_APPROVED
        ) {
            throw new OfferException('Only open offers can be accepted.');
        }
        if (CLOSED_PROPERTY_STATUSES.contains(property.Status__c)) {
            throw new OfferException(
                'This property is already ' +
                    property.Status__c +
                    ' and cannot accept another offer.'
            );
        }

        List<Offer__c> changes = new List<Offer__c>{
            new Offer__c(Id = offer.Id, Status__c = STATUS_ACCEPTED)
        };
        for (Offer__c other : [
            SELECT Id
            FROM Offer__c
            WHERE
                Property__c = :offer.Property__c
                AND Id != :offer.Id
                AND Status__c IN :OPEN_STATUSES
            WITH USER_MODE
        ]) {
            changes.add(
                new Offer__c(Id = other.Id, Status__c = STATUS_REJECTED)
            );
        }
        updateStatuses(changes);

        try {
            update as user new Property__c(
                Id = property.Id,
                Status__c = 'Under Agreement',
                Date_Agreement__c = Date.today()
            );
        } catch (DmlException e) {
            throw new OfferException(e.getDmlMessage(0));
        }
    }

    /**
     * Before-insert rules: validates the offer and stamps % below asking and
     * the initial status. Runs for every insert path, not just the LWC.
     */
    public static void applySubmissionRules(List<Offer__c> offers) {
        Set<Id> propertyIds = new Set<Id>();
        for (Offer__c offer : offers) {
            if (offer.Property__c != null) {
                propertyIds.add(offer.Property__c);
            }
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
            if (String.isBlank(offer.Buyer_Name__c)) {
                offer.Buyer_Name__c.addError('Enter the buyer name.');
            } else if (offer.Amount__c == null || offer.Amount__c <= 0) {
                offer.Amount__c.addError(
                    'Offer amount must be greater than zero.'
                );
            } else if (property == null) {
                offer.addError('Property not found.');
            } else if (CLOSED_PROPERTY_STATUSES.contains(property.Status__c)) {
                offer.addError(
                    'This property is ' +
                        property.Status__c +
                        ' and is not accepting offers.'
                );
            } else if (property.Price__c == null || property.Price__c <= 0) {
                offer.addError(
                    'This property has no asking price, so offers cannot be evaluated.'
                );
            } else {
                offer.Percent_Below_Asking__c = calculatePercentBelowAsking(
                    property.Price__c,
                    offer.Amount__c
                );
                offer.Status__c = needsApproval(offer.Percent_Below_Asking__c)
                    ? STATUS_NEEDS_APPROVAL
                    : STATUS_SUBMITTED;
            }
        }
    }

    /**
     * Before-update rules: amount and % below asking are immutable, and status
     * may only change through approveOffer, acceptOffer or rejectOffer.
     */
    public static void enforceUpdateRules(
        List<Offer__c> offers,
        Map<Id, Offer__c> oldOffers
    ) {
        for (Offer__c offer : offers) {
            Offer__c old = oldOffers.get(offer.Id);
            if (offer.Amount__c != old.Amount__c) {
                offer.Amount__c.addError(
                    'Offer amount cannot be changed after submission.'
                );
            }
            if (offer.Percent_Below_Asking__c != old.Percent_Below_Asking__c) {
                offer.Percent_Below_Asking__c.addError(
                    '% below asking is calculated on submission and cannot be changed.'
                );
            }
            if (offer.Status__c == old.Status__c) {
                continue;
            }
            if (!statusChangeInProgress) {
                offer.Status__c.addError(
                    'Offer status can only be changed with Approve, Accept or Reject.'
                );
            } else if (
                !ALLOWED_TRANSITIONS.containsKey(old.Status__c) ||
                !ALLOWED_TRANSITIONS.get(old.Status__c)
                    .contains(offer.Status__c)
            ) {
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

    private static Offer__c getOfferForUpdate(Id offerId) {
        List<Offer__c> offers = [
            SELECT Id, Property__c, Status__c
            FROM Offer__c
            WHERE Id = :offerId
            WITH USER_MODE
            FOR UPDATE
        ];
        if (offers.isEmpty()) {
            throw new OfferException('Offer not found.');
        }
        return offers[0];
    }

    private static void updateStatuses(List<Offer__c> offers) {
        statusChangeInProgress = true;
        try {
            update as user offers;
        } catch (DmlException e) {
            throw new OfferException(e.getDmlMessage(0));
        } finally {
            statusChangeInProgress = false;
        }
    }
}
