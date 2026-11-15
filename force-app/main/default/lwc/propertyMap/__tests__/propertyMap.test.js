import { createElement } from '@lwc/engine-dom';
import PropertyMap from 'c/propertyMap';
import { getRecord } from 'lightning/uiRecordApi';
import {
    publish,
    subscribe,
    unsubscribe,
    MessageContext
} from 'lightning/messageService';
import PROPERTYSELECTEDMC from '@salesforce/messageChannel/PropertySelected__c';

// Realistic property record
const mockPropertyRecord = require('./data/propertyRecord.json');
const EXPECTED_MAP_MARKERS = [
    {
        location: {
            Latitude: mockPropertyRecord.fields.Location__Latitude__s.value,
            Longitude: mockPropertyRecord.fields.Location__Longitude__s.value
        },
        title: `${mockPropertyRecord.fields.Name.value}`,
        description: `<b>Address</b>: ${mockPropertyRecord.fields.Address__c.value}`,
        mapIcon: {
            path: 'M1472 992v480q0 26-19 45t-45 19h-384v-384h-256v384h-384q-26 0-45-19t-19-45v-480q0-1 .5-3t.5-3l575-474 575 474q1 2 1 6zm223-69l-62 74q-8 9-21 11h-3q-13 0-21-7l-692-577-692 577q-12 8-24 7-13-2-21-11l-62-74q-8-10-7-23.5t11-21.5l719-599q32-26 76-26t76 26l244 204v-195q0-14 9-23t23-9h192q14 0 23 9t9 23v408l219 182q10 8 11 21.5t-7 23.5z',
            fillColor: '#f28b00',
            fillOpacity: 1,
            strokeWeight: 1,
            scale: 0.02
        }
    }
];

describe('c-property-map', () => {
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

    it('renders an error panel when no property is selected', async () => {
        const element = createElement('c-property-map', {
            is: PropertyMap
        });

        document.body.appendChild(element);

        // Wait for any asynchronous DOM updates
        await flushPromises();

        const panelEl = element.shadowRoot.querySelector('c-error-panel');
        expect(panelEl).not.toBeNull();
    });

    it('renders a map when a property is selected', async () => {
        const element = createElement('c-property-map', {
            is: PropertyMap
        });
        document.body.appendChild(element);

        // Simulate property selection
        getRecord.emit(mockPropertyRecord);

        // Wait for any asynchronous DOM updates
        await flushPromises();

        const mapEl = element.shadowRoot.querySelector('lightning-map');
        expect(mapEl).not.toBeNull();
        expect(mapEl.mapMarkers).toStrictEqual(EXPECTED_MAP_MARKERS);
    });

    it('is accessible when property is selected', async () => {
        const element = createElement('c-property-map', {
            is: PropertyMap
        });

        document.body.appendChild(element);

        // Simulate property selection
        getRecord.emit(mockPropertyRecord);

        // Wait for any asynchronous DOM updates
        await flushPromises();

        await expect(element).toBeAccessible();
    });

    it('is accessible when property is not selected', async () => {
        const element = createElement('c-property-map', {
            is: PropertyMap
        });

        document.body.appendChild(element);

        await expect(element).toBeAccessible();
    });

    it('shows the property address as the card title', async () => {
        const element = createElement('c-property-map', {
            is: PropertyMap
        });
        document.body.appendChild(element);

        getRecord.emit(mockPropertyRecord);

        await flushPromises();

        const cardEl = element.shadowRoot.querySelector('lightning-card');
        expect(cardEl.title).toBe(
            `${mockPropertyRecord.fields.Address__c.value}, ${mockPropertyRecord.fields.City__c.value}`
        );
        expect(element.shadowRoot.querySelector('c-error-panel')).toBeNull();
    });

    it('renders an error panel and clears markers when getRecord returns an error', async () => {
        const element = createElement('c-property-map', {
            is: PropertyMap
        });
        document.body.appendChild(element);

        getRecord.emit(mockPropertyRecord);
        await flushPromises();
        getRecord.error();
        await flushPromises();

        const panelEl = element.shadowRoot.querySelector('c-error-panel');
        expect(panelEl).not.toBeNull();
        expect(panelEl.friendlyMessage).toBe('Error retrieving map');
        const mapEl = element.shadowRoot.querySelector('lightning-map');
        expect(mapEl.mapMarkers).toStrictEqual([]);
        const cardEl = element.shadowRoot.querySelector('lightning-card');
        expect(cardEl.title).toBeUndefined();
    });

    it('passes the recordId to getRecord', async () => {
        const element = createElement('c-property-map', {
            is: PropertyMap
        });
        element.recordId = mockPropertyRecord.id;
        document.body.appendChild(element);

        await flushPromises();

        expect(element.recordId).toBe(mockPropertyRecord.id);
        expect(getRecord.getLastConfig().recordId).toBe(mockPropertyRecord.id);
    });

    it('registers the PropertySelected subscriber during the component lifecycle', () => {
        const element = createElement('c-property-map', {
            is: PropertyMap
        });
        document.body.appendChild(element);

        expect(subscribe).toHaveBeenCalled();
        expect(subscribe.mock.calls[0][1]).toBe(PROPERTYSELECTEDMC);
    });

    it('unregisters the PropertySelected subscriber when removed from the DOM', () => {
        const element = createElement('c-property-map', {
            is: PropertyMap
        });
        document.body.appendChild(element);
        document.body.removeChild(element);

        expect(unsubscribe).toHaveBeenCalled();
    });

    it('invokes getRecord with the published propertyId', async () => {
        const element = createElement('c-property-map', {
            is: PropertyMap
        });
        document.body.appendChild(element);

        publish(MessageContext, PROPERTYSELECTEDMC, {
            propertyId: mockPropertyRecord.id
        });

        await flushPromises();

        expect(element.recordId).toBe(mockPropertyRecord.id);
        expect(getRecord.getLastConfig().recordId).toBe(mockPropertyRecord.id);
    });
});
