public with sharing class OfferService {
    public class OfferException extends Exception {
    }
    private static Boolean changingStatus = false;
    public static Boolean isChangingStatus() {
        return changingStatus;
    }
    public static Boolean canApprove() {
        return FeatureManagement.checkPermission('Approve_Offers');
    }
    public static Id submit(Id propertyId, String buyerName, Decimal amount) {
        if (
            propertyId == null ||
            String.isBlank(buyerName) ||
            amount == null ||
            amount <= 0
        ) {
            throw new OfferException(
                'Property, buyer name and a positive offer amount are required.'
            );
        }
        Offer__c offer = new Offer__c(
            Property__c = propertyId,
            Buyer_Name__c = buyerName.trim(),
            Amount__c = amount
        );
        insert as user offer;
        return offer.Id;
    }
    public static void approve(Id offerId) {
        if (!canApprove()) {
            throw new OfferException('Broker approval permission is required.');
        }
        changeStatus(offerId, 'Approved');
    }
    public static void accept(Id offerId) {
        changeStatus(offerId, 'Accepted');
    }
    public static void reject(Id offerId) {
        changeStatus(offerId, 'Rejected');
    }
    private static void changeStatus(Id offerId, String target) {
        Offer__c initial = [
            SELECT Property__c
            FROM Offer__c
            WHERE Id = :offerId
            WITH USER_MODE
        ];
        Property__c property = [
            SELECT Id, Status__c
            FROM Property__c
            WHERE Id = :initial.Property__c
            WITH USER_MODE
            FOR UPDATE
        ];
        Offer__c offer = [
            SELECT Id, Status__c
            FROM Offer__c
            WHERE Id = :offerId
            WITH USER_MODE
        ];
        if (offer.Status__c == 'Accepted' || offer.Status__c == 'Rejected') {
            throw new OfferException('This offer is already final.');
        }
        if (target == 'Approved' && offer.Status__c != 'Needs Approval') {
            throw new OfferException(
                'Only offers needing approval can be approved.'
            );
        }
        if (target == 'Accepted') {
            if (
                property.Status__c == 'Closed' ||
                property.Status__c == 'Under Agreement'
            ) {
                throw new OfferException(
                    'This property is no longer available.'
                );
            }
            if (offer.Status__c == 'Needs Approval') {
                throw new OfferException(
                    'Broker approval is required before accepting this offer.'
                );
            }
        }
        List<Offer__c> updates = new List<Offer__c>{
            new Offer__c(Id = offerId, Status__c = target)
        };
        if (target == 'Accepted') {
            for (Offer__c other : [
                SELECT Id
                FROM Offer__c
                WHERE
                    Property__c = :property.Id
                    AND Id != :offerId
                    AND Status__c IN ('Submitted', 'Needs Approval', 'Approved')
                WITH USER_MODE
            ]) {
                updates.add(
                    new Offer__c(Id = other.Id, Status__c = 'Rejected')
                );
            }
        }
        Savepoint checkpoint = Database.setSavepoint();
        try {
            changingStatus = true;
            update as user updates;
            if (target == 'Accepted') {
                update as user new Property__c(
                    Id = property.Id,
                    Status__c = 'Under Agreement',
                    Date_Agreement__c = Date.today()
                );
            }
        } catch (Exception e) {
            Database.rollback(checkpoint);
            throw e;
        } finally {
            changingStatus = false;
        }
    }
}
