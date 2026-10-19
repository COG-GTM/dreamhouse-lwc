@isTest
public class OfferTestFactory {
    public static final String AGENT_LAST_NAME = 'OfferAgent';
    public static final String BROKER_LAST_NAME = 'OfferBroker';
    public static final Decimal ASKING_PRICE = 845000;

    public static void createUsersAndProperty() {
        System.runAs(new User(Id = UserInfo.getUserId())) {
            User agent = buildUser(AGENT_LAST_NAME);
            User broker = buildUser(BROKER_LAST_NAME);
            insert new List<User>{ agent, broker };

            Id dreamhouse = permissionSetId('dreamhouse');
            Id brokerPermissionSet = permissionSetId('Dreamhouse_Broker');
            insert new List<PermissionSetAssignment>{
                new PermissionSetAssignment(
                    AssigneeId = agent.Id,
                    PermissionSetId = dreamhouse
                ),
                new PermissionSetAssignment(
                    AssigneeId = broker.Id,
                    PermissionSetId = dreamhouse
                ),
                new PermissionSetAssignment(
                    AssigneeId = broker.Id,
                    PermissionSetId = brokerPermissionSet
                )
            };
        }
        insert new Property__c(
            Name = 'Offer Test Property',
            Price__c = ASKING_PRICE,
            Status__c = 'Available'
        );
    }

    public static User agent() {
        return [SELECT Id FROM User WHERE LastName = :AGENT_LAST_NAME LIMIT 1];
    }

    public static User broker() {
        return [
            SELECT Id
            FROM User
            WHERE LastName = :BROKER_LAST_NAME
            LIMIT 1
        ];
    }

    public static Property__c property() {
        return [
            SELECT Id, Price__c, Status__c, Date_Agreement__c
            FROM Property__c
            WHERE Name = 'Offer Test Property'
            LIMIT 1
        ];
    }

    public static Offer__c offer(Id offerId) {
        return [
            SELECT
                Id,
                Buyer_Name__c,
                Amount__c,
                Percent_Below_Asking__c,
                Status__c
            FROM Offer__c
            WHERE Id = :offerId
        ];
    }

    private static Id permissionSetId(String name) {
        return [SELECT Id FROM PermissionSet WHERE Name = :name LIMIT 1].Id;
    }

    private static User buildUser(String lastName) {
        Profile standardUser = [
            SELECT Id
            FROM Profile
            WHERE Name = 'Standard User'
            LIMIT 1
        ];
        String unique =
            lastName +
            UserInfo.getOrganizationId() +
            String.valueOf(Crypto.getRandomInteger()).replace('-', '');
        return new User(
            Alias = lastName.left(8),
            Email = lastName + '@dreamhouse.test',
            EmailEncodingKey = 'UTF-8',
            FirstName = 'Test',
            LastName = lastName,
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            ProfileId = standardUser.Id,
            TimeZoneSidKey = 'America/Los_Angeles',
            Username = unique + '@dreamhouse.test'
        );
    }
}
