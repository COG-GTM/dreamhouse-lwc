import { createElement } from '@lwc/engine-dom';
import PropertyLocation from 'c/propertyLocation';
import { getRecord } from 'lightning/uiRecordApi';
import {
    getLocationService,
    setDeviceLocationServiceAvailable
} from 'lightning/mobileCapabilities';
import { mockGeolocation } from '../../../../../test/jest-mocks/global/navigator';

// Realistic property record
const mockPropertyRecord = require('./data/getRecord.json');

const checkDistanceCalculation = (element) => {
    const latitudeEl = element.shadowRoot.querySelector(
        'div.location .latitude'
    );
    expect(latitudeEl).not.toBe(null);
    const longitudeEl = element.shadowRoot.querySelector(
        'div.location .longitude'
    );
    expect(longitudeEl).not.toBe(null);
    const formattedNumberEl = element.shadowRoot.querySelector(
        'div.location lightning-formatted-number'
    );
    expect(formattedNumberEl).not.toBe(null);

    // Compare with coordinates in mobileCapabilities.js mock
    expect(latitudeEl.textContent.trim()).toBe('42.361145');
    expect(longitudeEl.textContent.trim()).toBe('-71.057083');
    // Distance between mocked property and mocked location
    expect(formattedNumberEl.value).toBe(1444.43371701009);
};

describe('c-property-location', () => {
    afterEach(() => {
        // The jsdom instance is shared across test cases in a single file so reset the DOM
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
        jest.clearAllMocks();
    });

    // Helper function to wait until the microtask queue is empty.
    // Used when having to wait for asynchronous DOM updates.
    async function flushPromises() {
        return Promise.resolve();
    }

    it('renders an error panel when no location services are available', async () => {
        const element = createElement('c-property-location', {
            is: PropertyLocation
        });

        document.body.appendChild(element);

        // Wait for any asynchronous DOM updates
        await flushPromises();

        const panelEl = element.shadowRoot.querySelector('c-error-panel');
        expect(panelEl).not.toBeNull();
    });

    it('renders an error panel when getRecord returns an error', async () => {
        const element = createElement('c-property-location', {
            is: PropertyLocation
        });

        document.body.appendChild(element);

        // Simulate error
        getRecord.error();

        // Wait for any asynchronous DOM updates
        await flushPromises();

        const panelEl = element.shadowRoot.querySelector('c-error-panel');
        expect(panelEl).not.toBeNull();
    });

    // eslint-disable-next-line jest/expect-expect
    it('renders coordinates and distance when browser location is available', async () => {
        // Simulate browser location
        global.navigator.geolocation = mockGeolocation;

        const element = createElement('c-property-location', {
            is: PropertyLocation
        });
        element.recordId = mockPropertyRecord.id;
        document.body.appendChild(element);

        // Simulate property selection
        getRecord.emit(mockPropertyRecord);

        // Wait for any asynchronous DOM updates
        await flushPromises();

        checkDistanceCalculation(element);
    });

    // eslint-disable-next-line jest/expect-expect
    it('renders coordinates and distance when device location is available', async () => {
        // Simulate device location is available
        setDeviceLocationServiceAvailable(true);

        const element = createElement('c-property-location', {
            is: PropertyLocation
        });
        element.recordId = mockPropertyRecord.id;
        document.body.appendChild(element);

        // Simulate property selection
        getRecord.emit(mockPropertyRecord);

        // Wait for any asynchronous DOM updates
        await flushPromises();

        checkDistanceCalculation(element);
    });

    it('is accessible when panel is shown', async () => {
        // Simulate device location is available
        setDeviceLocationServiceAvailable(true);

        const element = createElement('c-property-location', {
            is: PropertyLocation
        });
        element.recordId = mockPropertyRecord.id;
        document.body.appendChild(element);

        // Simulate property selection
        getRecord.emit(mockPropertyRecord);

        // Wait for any asynchronous DOM updates
        await flushPromises();

        await expect(element).toBeAccessible();
    });

    it('renders an error panel when the device location request fails', async () => {
        const locationError = { message: 'Location permission denied' };
        getLocationService.mockImplementationOnce(() => ({
            isAvailable: () => true,
            getCurrentPosition: () => Promise.reject(locationError)
        }));

        const element = createElement('c-property-location', {
            is: PropertyLocation
        });
        element.recordId = mockPropertyRecord.id;
        document.body.appendChild(element);

        getRecord.emit(mockPropertyRecord);

        await flushPromises();
        await flushPromises();

        const panelEl = element.shadowRoot.querySelector('c-error-panel');
        expect(panelEl).not.toBeNull();
        expect(panelEl.errors).toEqual(locationError);
    });

    it('renders an error panel when the browser location request fails', async () => {
        setDeviceLocationServiceAvailable(false);
        const locationError = { code: 1, message: 'User denied Geolocation' };
        global.navigator.geolocation = {
            getCurrentPosition: jest.fn((success, error) =>
                error(locationError)
            )
        };

        const element = createElement('c-property-location', {
            is: PropertyLocation
        });
        element.recordId = mockPropertyRecord.id;
        document.body.appendChild(element);

        getRecord.emit(mockPropertyRecord);

        await flushPromises();

        const panelEl = element.shadowRoot.querySelector('c-error-panel');
        expect(panelEl).not.toBeNull();
        expect(panelEl.errors).toEqual(locationError);
    });

    it('renders a spinner until the property and location are both known', async () => {
        setDeviceLocationServiceAvailable(false);
        global.navigator.geolocation = mockGeolocation;

        const element = createElement('c-property-location', {
            is: PropertyLocation
        });
        element.recordId = mockPropertyRecord.id;
        document.body.appendChild(element);

        await flushPromises();

        expect(
            element.shadowRoot.querySelector('lightning-spinner')
        ).not.toBeNull();
        expect(element.shadowRoot.querySelector('div.location')).toBeNull();
    });
});
