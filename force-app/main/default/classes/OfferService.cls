/**
 * Offers on a property, with discount approval.
 * Offers more than 10% below asking need a broker with the Approve_Offers
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
    public static final Set<String> CLOSED_PROPERTY_STATUSES = new Set<String>{
        PROPERTY_UNDER_AGREEMENT,
        'Contracted',
        'Closed'
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

    // Set only while this service writes offers, so the trigger can tell
    // approve/accept/reject apart from direct edits.
    private static Boolean serviceWrite = false;

    public class OfferException extends Exception {
    }

    public class OfferContext {
        @AuraEnabled
        public Decimal askingPrice;
        @AuraEnabled
        public String propertyStatus;
        @AuraEnabled
        public Boolean propertyOpen;
        @AuraEnabled
        public Boolean canApprove;
        @AuraEnabled
        public Decimal approvalThreshold;
        @AuraEnabled
        public List<Offer__c> offers;
    }

    public static Decimal percentBelowAsking(
        Decimal askingPrice,
        Decimal amount
    ) {
        return ((askingPrice - amount) * 100)
            .divide(askingPrice, 1, System.RoundingMode.HALF_UP);
    }

    public static Boolean requiresApproval(Decimal percentBelow) {
        return percentBelow > APPROVAL_THRESHOLD;
    }

    public static Boolean canApprove() {
        return FeatureManagement.checkPermission(APPROVE_PERMISSION);
    }

    public static OfferContext getOfferContext(Id propertyId) {
        Property__c property = [
            SELECT Id, Price__c, Status__c
            FROM Property__c
            WHERE Id = :propertyId
            WITH USER_MODE
        ];
        OfferContext context = new OfferContext();
        context.askingPrice = property.Price__c;
        context.propertyStatus = property.Status__c;
        context.propertyOpen = !CLOSED_PROPERTY_STATUSES.contains(
            property.Status__c
        );
        context.canApprove = canApprove();
        context.approvalThreshold = APPROVAL_THRESHOLD;
        context.offers = [
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
        return context;
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
            throw new OfferException(
                'The offer amount must be greater than zero.'
            );
        }
        Property__c property = lockProperty(propertyId);
        assertPropertyOpen(property);
        assertHasAskingPrice(property);

        Decimal percentBelow = percentBelowAsking(property.Price__c, amount);
        Offer__c offer = new Offer__c(
            Property__c = propertyId,
            Buyer_Name__c = buyerName.trim(),
            Amount__c = amount,
            Percent_Below_Asking__c = percentBelow,
            Status__c = requiresApproval(percentBelow)
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

    public static void approveOffer(Id offerId) {
        if (!canApprove()) {
            throw new OfferException(
                'Only brokers with the Approve Offers permission can approve offers.'
            );
        }
        Property__c property = lockProperty(propertyIdFor(offerId));
        Offer__c offer = lockOffer(offerId);
        assertPropertyOpen(property);
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

    public static void acceptOffer(Id offerId) {
        Property__c property = lockProperty(propertyIdFor(offerId));
        Offer__c offer = lockOffer(offerId);
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
            throw new OfferException(
                'Only submitted or approved offers can be accepted.'
            );
        }
        if (offer.Status__c == STATUS_SUBMITTED) {
            assertHasAskingPrice(property);
            Decimal currentPercent = percentBelowAsking(
                property.Price__c,
                offer.Amount__c
            );
            if (requiresApproval(currentPercent)) {
                throw new OfferException(
                    'The asking price has changed. This offer is now ' +
                        currentPercent +
                        '% below asking and needs broker approval.'
                );
            }
        }

        List<Offer__c> updates = new List<Offer__c>{
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
        writeStatuses(updates);

        update as user new Property__c(
            Id = property.Id,
            Status__c = PROPERTY_UNDER_AGREEMENT,
            Date_Agreement__c = Date.today()
        );
    }

    public static void rejectOffer(Id offerId) {
        lockProperty(propertyIdFor(offerId));
        Offer__c offer = lockOffer(offerId);
        if (!OPEN_OFFER_STATUSES.contains(offer.Status__c)) {
            throw new OfferException('Only open offers can be rejected.');
        }
        writeStatuses(
            new List<Offer__c>{
                new Offer__c(Id = offer.Id, Status__c = STATUS_REJECTED)
            }
        );
    }

    public static void handleBeforeInsert(List<Offer__c> offers) {
        if (serviceWrite) {
            return;
        }
        for (Offer__c offer : offers) {
            offer.addError(
                'Offers must be submitted from the Offers card on the property.'
            );
        }
    }

    public static void handleBeforeUpdate(
        List<Offer__c> offers,
        Map<Id, Offer__c> oldOffers
    ) {
        for (Offer__c offer : offers) {
            Offer__c old = oldOffers.get(offer.Id);
            if (offer.Amount__c != old.Amount__c) {
                offer.Amount__c.addError(
                    'The offer amount cannot be changed after submission.'
                );
            }
            if (offer.Percent_Below_Asking__c != old.Percent_Below_Asking__c) {
                offer.Percent_Below_Asking__c.addError(
                    '% below asking cannot be changed after submission.'
                );
            }
            if (offer.Status__c == old.Status__c) {
                continue;
            }
            if (!serviceWrite) {
                offer.Status__c.addError(
                    'Use Approve, Accept or Reject to change an offer status.'
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

    private static void writeStatuses(List<Offer__c> offers) {
        serviceWrite = true;
        try {
            update as user offers;
        } finally {
            serviceWrite = false;
        }
    }

    private static Id propertyIdFor(Id offerId) {
        List<Offer__c> offers = [
            SELECT Property__c
            FROM Offer__c
            WHERE Id = :offerId
            WITH USER_MODE
        ];
        if (offers.isEmpty()) {
            throw new OfferException('Offer not found.');
        }
        return offers[0].Property__c;
    }

    private static Property__c lockProperty(Id propertyId) {
        List<Property__c> properties = [
            SELECT Id, Price__c, Status__c
            FROM Property__c
            WHERE Id = :propertyId
            WITH USER_MODE
            FOR UPDATE
        ];
        if (properties.isEmpty()) {
            throw new OfferException('Property not found.');
        }
        return properties[0];
    }

    private static Offer__c lockOffer(Id offerId) {
        return [
            SELECT Id, Property__c, Amount__c, Status__c
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

    private static void assertHasAskingPrice(Property__c property) {
        if (property.Price__c == null || property.Price__c <= 0) {
            throw new OfferException(
                'This property has no asking price, so offers cannot be priced against it.'
            );
        }
    }
}
