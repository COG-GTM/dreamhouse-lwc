public with sharing class GeocodingService {
    private static final String BASE_URL = 'callout:OpenStreetMap/search?format=json';

    /**
     * Invocable method that geocodes a list of addresses
     * @param addresses List of addresses to geocode
     * @return List of coordinates, one per input address. Coordinates are blank
     * when the address is empty or when the geocoding service returns no match.
     */
    @InvocableMethod(callout=true label='Geocode address')
    public static List<Coordinates> geocodeAddresses(
        List<GeocodingAddress> addresses
    ) {
        List<Coordinates> computedCoordinates = new List<Coordinates>();

        for (GeocodingAddress address : addresses) {
            String geocodingUrl = BASE_URL;
            geocodingUrl += buildParameter('street', address.street);
            geocodingUrl += buildParameter('city', address.city);
            geocodingUrl += buildParameter('state', address.state);
            geocodingUrl += buildParameter('country', address.country);
            geocodingUrl += buildParameter('postalcode', address.postalcode);

            Coordinates coords = new Coordinates();
            if (geocodingUrl != BASE_URL) {
                Http http = new Http();
                HttpRequest request = new HttpRequest();
                request.setEndpoint(geocodingUrl);
                request.setMethod('GET');
                request.setHeader(
                    'http-referer',
                    URL.getOrgDomainUrl().toExternalForm()
                );
                HttpResponse response = http.send(request);
                if (response.getStatusCode() == 200) {
                    Coordinates firstMatch = getFirstMatch(response.getBody());
                    if (firstMatch != null) {
                        coords = firstMatch;
                    }
                } else {
                    System.debug(
                        LoggingLevel.ERROR,
                        'Geocoding callout failed with status ' +
                            response.getStatusCode() +
                            ' ' +
                            response.getStatus()
                    );
                }
            }

            computedCoordinates.add(coords);
        }
        return computedCoordinates;
    }

    private static String buildParameter(String name, String value) {
        if (String.isBlank(value)) {
            return '';
        }
        return '&' + name + '=' + EncodingUtil.urlEncode(value, 'UTF-8');
    }

    private static Coordinates getFirstMatch(String responseBody) {
        if (String.isBlank(responseBody)) {
            return null;
        }
        List<Coordinates> deserializedCoords;
        try {
            deserializedCoords = (List<Coordinates>) JSON.deserialize(
                responseBody,
                List<Coordinates>.class
            );
        } catch (JSONException e) {
            System.debug(
                LoggingLevel.ERROR,
                'Failed to parse geocoding response: ' + e.getMessage()
            );
            return null;
        }
        if (deserializedCoords == null || deserializedCoords.isEmpty()) {
            return null;
        }
        return deserializedCoords[0];
    }

    public class GeocodingAddress {
        @InvocableVariable
        public String street;
        @InvocableVariable
        public String city;
        @InvocableVariable
        public String state;
        @InvocableVariable
        public String country;
        @InvocableVariable
        public String postalcode;
    }

    public class Coordinates {
        @InvocableVariable
        public Decimal lat;
        @InvocableVariable
        public Decimal lon;
    }
}
