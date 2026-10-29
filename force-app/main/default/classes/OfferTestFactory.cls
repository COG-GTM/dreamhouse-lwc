@IsTest
public class OfferTestFactory {
    public static final String AGENT_USERNAME_PREFIX = 'offers.agent';
    public static final String BROKER_USERNAME_PREFIX = 'offers.broker';

    public static Property__c createProperty(
        String name,
        Decimal price,
        String status
    ) {
        Property__c property = new Property__c(
            Name = name,
            Price__c = price,
            Status__c = status,
            Beds__c = 3,
            Baths__c = 2
        );
        insert property;
        return property;
    }

    // Creates an agent (dreamhouse only) and a broker (dreamhouse +
    // Dreamhouse_Broker). Call from @TestSetup before inserting data records.
    public static void createUsers() {
        System.runAs(new User(Id = UserInfo.getUserId())) {
            Profile standardProfile = [
                SELECT Id
                FROM Profile
                WHERE Name = 'Standard User'
                LIMIT 1
            ];
            User agent = buildUser(standardProfile.Id, AGENT_USERNAME_PREFIX);
            User broker = buildUser(standardProfile.Id, BROKER_USERNAME_PREFIX);
            insert new List<User>{ agent, broker };

            Map<String, Id> permissionSets = new Map<String, Id>();
            for (PermissionSet ps : [
                SELECT Id, Name
                FROM PermissionSet
                WHERE Name IN ('dreamhouse', 'Dreamhouse_Broker')
            ]) {
                permissionSets.put(ps.Name, ps.Id);
            }
            insert new List<PermissionSetAssignment>{
                new PermissionSetAssignment(
                    AssigneeId = agent.Id,
                    PermissionSetId = permissionSets.get('dreamhouse')
                ),
                new PermissionSetAssignment(
                    AssigneeId = broker.Id,
                    PermissionSetId = permissionSets.get('dreamhouse')
                ),
                new PermissionSetAssignment(
                    AssigneeId = broker.Id,
                    PermissionSetId = permissionSets.get('Dreamhouse_Broker')
                )
            };
        }
    }

    public static User agent() {
        return findUser(AGENT_USERNAME_PREFIX);
    }

    public static User broker() {
        return findUser(BROKER_USERNAME_PREFIX);
    }

    private static User findUser(String prefix) {
        String pattern = prefix + '%';
        return [SELECT Id FROM User WHERE Username LIKE :pattern LIMIT 1];
    }

    private static User buildUser(Id profileId, String prefix) {
        String unique = prefix + '.' + Crypto.getRandomInteger();
        return new User(
            Alias = prefix.right(8),
            Email = unique + '@example.com',
            EmailEncodingKey = 'UTF-8',
            LastName = prefix,
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            ProfileId = profileId,
            TimeZoneSidKey = 'America/Los_Angeles',
            Username = unique + '@dreamhouse-offers.test'
        );
    }
}
