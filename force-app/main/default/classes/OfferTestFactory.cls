@isTest
public class OfferTestFactory {
    public static final Decimal ASKING_PRICE = 845000;
    private static final String AGENT_LAST_NAME = 'OfferTestAgent';
    private static final String BROKER_LAST_NAME = 'OfferTestBroker';

    public static void createUsersAndProperty() {
        System.runAs(new User(Id = UserInfo.getUserId())) {
            Profile standardUser = [
                SELECT Id
                FROM Profile
                WHERE Name = 'Standard User'
                LIMIT 1
            ];
            User agent = newUser(standardUser.Id, AGENT_LAST_NAME);
            User broker = newUser(standardUser.Id, BROKER_LAST_NAME);
            insert new List<User>{ agent, broker };

            Map<String, Id> permSets = new Map<String, Id>();
            for (PermissionSet ps : [
                SELECT Id, Name
                FROM PermissionSet
                WHERE Name IN ('dreamhouse', 'Dreamhouse_Broker')
            ]) {
                permSets.put(ps.Name, ps.Id);
            }
            insert new List<PermissionSetAssignment>{
                assign(agent.Id, permSets.get('dreamhouse')),
                assign(broker.Id, permSets.get('dreamhouse')),
                assign(broker.Id, permSets.get('Dreamhouse_Broker'))
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
        return [SELECT Id FROM User WHERE LastName = :BROKER_LAST_NAME LIMIT 1];
    }

    public static Property__c property() {
        return [
            SELECT Id, Status__c, Date_Agreement__c
            FROM Property__c
            WHERE Name = 'Offer Test Property'
            LIMIT 1
        ];
    }

    public static Offer__c offer(Id offerId) {
        return [
            SELECT Id, Status__c, Amount__c, Percent_Below_Asking__c
            FROM Offer__c
            WHERE Id = :offerId
        ];
    }

    private static User newUser(Id profileId, String lastName) {
        String unique =
            lastName +
            String.valueOf(Crypto.getRandomInteger()).replace('-', '');
        return new User(
            ProfileId = profileId,
            LastName = lastName,
            Alias = lastName.right(8),
            Email = unique + '@example.com',
            Username = unique + '@dreamhouse-offers.test',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            TimeZoneSidKey = 'America/New_York'
        );
    }

    private static PermissionSetAssignment assign(Id userId, Id permSetId) {
        return new PermissionSetAssignment(
            AssigneeId = userId,
            PermissionSetId = permSetId
        );
    }
}
