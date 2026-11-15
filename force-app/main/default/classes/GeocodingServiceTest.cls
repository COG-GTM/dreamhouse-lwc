@isTest
private with sharing class GeocodingServiceTest {
    private static final String STREET = 'Camino del Jueves 26';
    private static final String CITY = 'Armilla';
    private static final String POSTAL_CODE = '18100';
    private static final String STATE = 'Granada';
    private static final String COUNTRY = 'Spain';
    private static final Decimal LATITUDE = 3.123;
    private static final Decimal LONGITUDE = 31.333;
    private static final String BASE_URL = 'https://nominatim.openstreetmap.org/search?format=json';
    private static final String SUCCESS_BODY =
        '[{"lat": ' +
        LATITUDE +
        ',"lon": ' +
        LONGITUDE +
        '}]';

    @isTest
    static void successResponse() {
        // GIVEN
        GeocodingService.GeocodingAddress address = new GeocodingService.GeocodingAddress();
        address.street = STREET;
        address.city = CITY;
        address.postalcode = POSTAL_CODE;
        address.state = STATE;
        address.country = COUNTRY;

        Test.setMock(
            HttpCalloutMock.class,
            new OpenStreetMapHttpCalloutMockImpl()
        );

        // WHEN
        List<GeocodingService.Coordinates> computedCoordinates = GeocodingService.geocodeAddresses(
            new List<GeocodingService.GeocodingAddress>{ address }
        );

        // THEN
        Assert.areEqual(1, computedCoordinates.size());
        Assert.areEqual(LATITUDE, computedCoordinates[0].lat);
        Assert.areEqual(LONGITUDE, computedCoordinates[0].lon);
    }
    @isTest
    static void blankAddress() {
        // GIVEN
        GeocodingService.GeocodingAddress address = new GeocodingService.GeocodingAddress();

        Test.setMock(
            HttpCalloutMock.class,
            new OpenStreetMapHttpCalloutMockImpl()
        );

        // WHEN
        List<GeocodingService.Coordinates> computedCoordinates = GeocodingService.geocodeAddresses(
            new List<GeocodingService.GeocodingAddress>{ address }
        );

        // THEN
        Assert.areEqual(1, computedCoordinates.size());
        Assert.isNull(computedCoordinates[0].lat);
        Assert.isNull(computedCoordinates[0].lon);
    }
    @isTest
    static void errorResponse() {
        // GIVEN
        GeocodingService.GeocodingAddress address = new GeocodingService.GeocodingAddress();
        address.street = STREET;
        address.city = CITY;
        address.postalcode = POSTAL_CODE;
        address.state = STATE;
        address.country = COUNTRY;

        Test.setMock(
            HttpCalloutMock.class,
            new OpenStreetMapHttpCalloutMockImplError()
        );

        // WHEN
        List<GeocodingService.Coordinates> computedCoordinates = GeocodingService.geocodeAddresses(
            new List<GeocodingService.GeocodingAddress>{ address }
        );

        // THEN
        Assert.areEqual(1, computedCoordinates.size());
        Assert.isNull(computedCoordinates[0].lat);
        Assert.isNull(computedCoordinates[0].lon);
    }

    @isTest
    static void noMatchResponse() {
        // GIVEN
        GeocodingService.GeocodingAddress address = new GeocodingService.GeocodingAddress();
        address.street = STREET;
        address.city = CITY;

        Test.setMock(
            HttpCalloutMock.class,
            new RecordingHttpCalloutMock(200, '[]')
        );

        // WHEN
        List<GeocodingService.Coordinates> computedCoordinates = GeocodingService.geocodeAddresses(
            new List<GeocodingService.GeocodingAddress>{ address }
        );

        // THEN
        Assert.areEqual(1, computedCoordinates.size());
        Assert.isNull(computedCoordinates[0].lat);
        Assert.isNull(computedCoordinates[0].lon);
    }

    @isTest
    static void requestIncludesAllAddressFields() {
        // GIVEN
        GeocodingService.GeocodingAddress address = new GeocodingService.GeocodingAddress();
        address.street = STREET;
        address.city = CITY;
        address.postalcode = POSTAL_CODE;
        address.state = STATE;
        address.country = COUNTRY;

        RecordingHttpCalloutMock mock = new RecordingHttpCalloutMock(
            200,
            SUCCESS_BODY
        );
        Test.setMock(HttpCalloutMock.class, mock);

        // WHEN
        GeocodingService.geocodeAddresses(
            new List<GeocodingService.GeocodingAddress>{ address }
        );

        // THEN
        Assert.areEqual(1, mock.requests.size());
        HttpRequest request = mock.requests[0];
        Assert.areEqual(
            BASE_URL +
                '&street=' +
                STREET +
                '&city=' +
                CITY +
                '&state=' +
                STATE +
                '&country=' +
                COUNTRY +
                '&postalcode=' +
                POSTAL_CODE,
            request.getEndpoint()
        );
        Assert.areEqual('GET', request.getMethod());
        Assert.areEqual(
            URL.getOrgDomainUrl().toExternalForm(),
            request.getHeader('http-referer')
        );
    }

    @isTest
    static void requestOmitsBlankAddressFields() {
        // GIVEN
        GeocodingService.GeocodingAddress address = new GeocodingService.GeocodingAddress();
        address.street = '  ';
        address.city = CITY;
        address.country = COUNTRY;

        RecordingHttpCalloutMock mock = new RecordingHttpCalloutMock(
            200,
            SUCCESS_BODY
        );
        Test.setMock(HttpCalloutMock.class, mock);

        // WHEN
        List<GeocodingService.Coordinates> computedCoordinates = GeocodingService.geocodeAddresses(
            new List<GeocodingService.GeocodingAddress>{ address }
        );

        // THEN
        Assert.areEqual(1, mock.requests.size());
        Assert.areEqual(
            BASE_URL + '&city=' + CITY + '&country=' + COUNTRY,
            mock.requests[0].getEndpoint()
        );
        Assert.areEqual(LATITUDE, computedCoordinates[0].lat);
        Assert.areEqual(LONGITUDE, computedCoordinates[0].lon);
    }

    @isTest
    static void multipleAddressesKeepInputOrder() {
        // GIVEN
        GeocodingService.GeocodingAddress fullAddress = new GeocodingService.GeocodingAddress();
        fullAddress.street = STREET;
        fullAddress.city = CITY;
        fullAddress.country = COUNTRY;
        GeocodingService.GeocodingAddress blankAddress = new GeocodingService.GeocodingAddress();
        GeocodingService.GeocodingAddress postalCodeOnly = new GeocodingService.GeocodingAddress();
        postalCodeOnly.postalcode = POSTAL_CODE;

        RecordingHttpCalloutMock mock = new RecordingHttpCalloutMock(
            200,
            SUCCESS_BODY
        );
        Test.setMock(HttpCalloutMock.class, mock);

        // WHEN
        Test.startTest();
        List<GeocodingService.Coordinates> computedCoordinates = GeocodingService.geocodeAddresses(
            new List<GeocodingService.GeocodingAddress>{
                fullAddress,
                blankAddress,
                postalCodeOnly
            }
        );
        Test.stopTest();

        // THEN
        Assert.areEqual(3, computedCoordinates.size());
        Assert.areEqual(LATITUDE, computedCoordinates[0].lat);
        Assert.areEqual(LONGITUDE, computedCoordinates[0].lon);
        Assert.isNull(computedCoordinates[1].lat);
        Assert.isNull(computedCoordinates[1].lon);
        Assert.areEqual(LATITUDE, computedCoordinates[2].lat);
        Assert.areEqual(LONGITUDE, computedCoordinates[2].lon);
        Assert.areEqual(
            2,
            mock.requests.size(),
            'Blank addresses must not trigger a callout'
        );
        Assert.areEqual(
            BASE_URL + '&postalcode=' + POSTAL_CODE,
            mock.requests[1].getEndpoint()
        );
    }

    @isTest
    static void emptyInputReturnsEmptyList() {
        // GIVEN
        RecordingHttpCalloutMock mock = new RecordingHttpCalloutMock(
            200,
            SUCCESS_BODY
        );
        Test.setMock(HttpCalloutMock.class, mock);

        // WHEN
        List<GeocodingService.Coordinates> computedCoordinates = GeocodingService.geocodeAddresses(
            new List<GeocodingService.GeocodingAddress>()
        );

        // THEN
        Assert.isTrue(computedCoordinates.isEmpty());
        Assert.isTrue(mock.requests.isEmpty());
    }

    public class RecordingHttpCalloutMock implements HttpCalloutMock {
        private final Integer statusCode;
        private final String body;
        public final List<HttpRequest> requests = new List<HttpRequest>();

        public RecordingHttpCalloutMock(Integer statusCode, String body) {
            this.statusCode = statusCode;
            this.body = body;
        }

        public HTTPResponse respond(HTTPRequest req) {
            requests.add(req);
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            res.setBody(body);
            res.setStatusCode(statusCode);
            return res;
        }
    }

    public class OpenStreetMapHttpCalloutMockImpl implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            res.setBody('[{"lat": ' + LATITUDE + ',"lon": ' + LONGITUDE + '}]');
            res.setStatusCode(200);
            return res;
        }
    }

    public class OpenStreetMapHttpCalloutMockImplError implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            res.setStatusCode(400);
            return res;
        }
    }
}
