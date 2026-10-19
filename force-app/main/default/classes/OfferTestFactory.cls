@IsTest
public class OfferTestFactory {
    private static final String DOMAIN = '@dreamhouse-offers.test';

    public static User createUser(String alias, Boolean isBroker) {
        Profile standard = [
            SELECT Id
            FROM Profile
            WHERE Name = 'Standard User'
            LIMIT 1
        ];
        User user = new User(
            Alias = alias.left(8),
            Email = alias + DOMAIN,
            Username = alias + '.' + Crypto.getRandomInteger() + DOMAIN,
            LastName = alias,
            ProfileId = standard.Id,
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            TimeZoneSidKey = 'America/New_York'
        );
        insert user;

        List<String> permissionSets = new List<String>{ 'dreamhouse' };
        if (isBroker) {
            permissionSets.add('Dreamhouse_Broker');
        }
        List<PermissionSetAssignment> assignments = new List<PermissionSetAssignment>();
        for (PermissionSet permissionSet : [
            SELECT Id
            FROM PermissionSet
            WHERE Name IN :permissionSets
        ]) {
            assignments.add(
                new PermissionSetAssignment(
                    AssigneeId = user.Id,
                    PermissionSetId = permissionSet.Id
                )
            );
        }
        insert assignments;
        return user;
    }

    public static User getUser(String alias) {
        return [
            SELECT Id
            FROM User
            WHERE Alias = :alias AND Email = :(alias + DOMAIN)
            LIMIT 1
        ];
    }
}
