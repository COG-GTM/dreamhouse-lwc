import { createElement } from '@lwc/engine-dom';
import PropertyTileList from 'c/propertyTileList';
import getPagedPropertyList from '@salesforce/apex/PropertyController.getPagedPropertyList';
import {
    publish,
    subscribe,
    unsubscribe,
    MessageContext
} from 'lightning/messageService';
import FILTERSCHANGEMC from '@salesforce/messageChannel/FiltersChange__c';
import PROPERTYSELECTEDMC from '@salesforce/messageChannel/PropertySelected__c';

// Realistic data with multiple records
const mockgetPagedPropertyList = require('./data/getPagedPropertyList.json');

// Mock getPagedPropertyList Apex wire adapter
jest.mock(
    '@salesforce/apex/PropertyController.getPagedPropertyList',
    () => {
        const {
            createApexTestWireAdapter
        } = require('@salesforce/sfdx-lwc-jest');
        return {
            default: createApexTestWireAdapter(jest.fn())
        };
    },
    { virtual: true }
);

describe('c-property-tile-list', () => {
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

    describe('@wire data', () => {
        it('renders properties when data returned', async () => {
            const element = createElement('c-property-tile-list', {
                is: PropertyTileList
            });
            document.body.appendChild(element);

            // Emit mock properties
            getPagedPropertyList.emit(mockgetPagedPropertyList);

            // Wait for any asynchronous DOM updates
            await flushPromises();

            const propertyTileEls =
                element.shadowRoot.querySelectorAll('c-property-tile');
            expect(propertyTileEls.length).toBe(
                mockgetPagedPropertyList.records.length
            );
        });

        it('renders error panel when error returned', async () => {
            const element = createElement('c-property-tile-list', {
                is: PropertyTileList
            });
            document.body.appendChild(element);

            // Emit error
            getPagedPropertyList.error();

            // Wait for any asynchronous DOM updates
            await flushPromises();

            const errorPanelEl =
                element.shadowRoot.querySelector('c-error-panel');
            expect(errorPanelEl).not.toBeNull();
        });
    });

    it('registers propertyFilters subscriber during the component lifecycle', () => {
        const element = createElement('c-property-tile-list', {
            is: PropertyTileList
        });
        document.body.appendChild(element);

        // Validate if subscriber got registered after connected to the DOM
        expect(subscribe).toHaveBeenCalled();
        expect(subscribe.mock.calls[0][1]).toBe(FILTERSCHANGEMC);
    });

    it('invokes getPagedPropertyList with the propertyFilters message payload value', async () => {
        const element = createElement('c-property-tile-list', {
            is: PropertyTileList
        });
        document.body.appendChild(element);

        // Simulate pulishing a message using FILTERSCHANGEMC message channel
        const messagePayload = {
            searchKey: 'victorian',
            maxPrice: 400000,
            minBedrooms: 4,
            minBathrooms: 2
        };
        publish(MessageContext, FILTERSCHANGEMC, messagePayload);

        // Wait for any asynchronous DOM updates
        await flushPromises();

        // The component subscription should cause getRecord to be invoked.
        // Below we test that it is invoked with the messagePayload value
        // that was published with the simulated publish invocation above.
        const receivedPayload = getPagedPropertyList.getLastConfig();
        expect(receivedPayload.searchKey).toBe(messagePayload.searchKey);
        expect(receivedPayload.maxPrice).toBe(messagePayload.maxPrice);
        expect(receivedPayload.minBedrooms).toBe(messagePayload.minBedrooms);
        expect(receivedPayload.minBathrooms).toBe(messagePayload.minBathrooms);
    });

    it('sends propertySelected event when c-property-tile selected', async () => {
        const element = createElement('c-property-tile-list', {
            is: PropertyTileList
        });
        document.body.appendChild(element);
        getPagedPropertyList.emit(mockgetPagedPropertyList);

        // Wait for any asynchronous DOM updates
        await flushPromises();

        const propertyTile =
            element.shadowRoot.querySelector('c-property-tile');
        const propertyId = mockgetPagedPropertyList.records[0].Id;
        propertyTile.dispatchEvent(
            new CustomEvent('selected', { detail: propertyId })
        );
        expect(publish).toHaveBeenCalledWith(undefined, PROPERTYSELECTEDMC, {
            propertyId
        });
    });

    it('unregisters the propertyFilters subscriber when removed from the DOM', () => {
        const subscription = { id: 'sub-1' };
        subscribe.mockReturnValueOnce(subscription);
        const element = createElement('c-property-tile-list', {
            is: PropertyTileList
        });
        document.body.appendChild(element);
        document.body.removeChild(element);

        expect(unsubscribe).toHaveBeenCalledWith(subscription);
    });

    it('passes paging info to c-paginator', async () => {
        const element = createElement('c-property-tile-list', {
            is: PropertyTileList
        });
        document.body.appendChild(element);
        getPagedPropertyList.emit(mockgetPagedPropertyList);

        await flushPromises();

        const paginatorEl = element.shadowRoot.querySelector('c-paginator');
        expect(paginatorEl.pageNumber).toBe(1);
        expect(paginatorEl.pageSize).toBe(9);
        expect(paginatorEl.totalItemCount).toBe(
            mockgetPagedPropertyList.totalItemCount
        );
        expect(getPagedPropertyList.getLastConfig()).toEqual({
            searchKey: '',
            maxPrice: 9999999,
            minBedrooms: 0,
            minBathrooms: 0,
            pageSize: 9,
            pageNumber: 1
        });
    });

    it('requests the next and previous pages from c-paginator events', async () => {
        const element = createElement('c-property-tile-list', {
            is: PropertyTileList
        });
        document.body.appendChild(element);
        getPagedPropertyList.emit(mockgetPagedPropertyList);

        await flushPromises();

        const paginatorEl = element.shadowRoot.querySelector('c-paginator');
        paginatorEl.dispatchEvent(new CustomEvent('next'));
        await flushPromises();
        expect(getPagedPropertyList.getLastConfig().pageNumber).toBe(2);
        expect(paginatorEl.pageNumber).toBe(2);

        paginatorEl.dispatchEvent(new CustomEvent('previous'));
        await flushPromises();
        expect(getPagedPropertyList.getLastConfig().pageNumber).toBe(1);
        expect(paginatorEl.pageNumber).toBe(1);
    });
});
