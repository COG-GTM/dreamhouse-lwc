import { createElement } from '@lwc/engine-dom';
import ListContactsFromDevice from 'c/listContactsFromDevice';
import {
    getContactsService,
    resetContactsServiceStubs,
    setContactsServiceAvailable,
    setContactsServiceContacts,
    setContactsServiceError
} from 'lightning/mobileCapabilities';

const MOCK_CONTACTS = [
    {
        Id: 'c1',
        name: { givenName: 'Ada', familyName: 'Lovelace' },
        phoneNumbers: [
            { value: '555-0100', label: 'mobile' },
            { value: '555-0101', label: 'work' }
        ]
    },
    {
        Id: 'c2',
        name: { givenName: 'Alan', familyName: 'Turing' },
        phoneNumbers: [{ value: '555-0200', label: 'home' }]
    }
];

describe('c-list-contacts-from-device', () => {
    afterEach(() => {
        // The jsdom instance is shared across test cases in a single file so reset the DOM
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
        resetContactsServiceStubs();
        jest.clearAllMocks();
    });

    // Helper function to wait until the microtask queue is empty.
    // Used when having to wait for asynchronous DOM updates.
    async function flushPromises() {
        return Promise.resolve();
    }

    function createComponent() {
        const element = createElement('c-list-contacts-from-device', {
            is: ListContactsFromDevice
        });
        document.body.appendChild(element);
        return element;
    }

    it('renders an error panel when the contacts service is not available', async () => {
        const element = createComponent();

        await flushPromises();

        const panelEl = element.shadowRoot.querySelector('c-error-panel');
        expect(panelEl).not.toBeNull();
        expect(panelEl.friendlyMessage).toBe('Error accessing device contacts');
        expect(panelEl.errors).toEqual({
            message: 'Contact service not available'
        });
        expect(
            element.shadowRoot.querySelector('lightning-spinner')
        ).toBeNull();
    });

    it('requests contacts with a permission rationale when the service is available', async () => {
        setContactsServiceAvailable(true);
        setContactsServiceContacts(MOCK_CONTACTS);

        createComponent();

        await flushPromises();

        const service = getContactsService.mock.results[0].value;
        expect(service.getContacts).toHaveBeenCalledTimes(1);
        expect(service.getContacts).toHaveBeenCalledWith({
            permissionRationaleText:
                'Allow access to your contacts to enable contacts processing.'
        });
    });

    it('renders device contacts with their phone numbers', async () => {
        setContactsServiceAvailable(true);
        setContactsServiceContacts(MOCK_CONTACTS);

        const element = createComponent();

        await flushPromises();
        await flushPromises();

        const contactEls = element.shadowRoot.querySelectorAll(
            'ul.slds-var-m-around_large > li'
        );
        expect(contactEls.length).toBe(MOCK_CONTACTS.length);
        expect(contactEls[0].textContent).toContain('Ada');
        expect(contactEls[0].textContent).toContain('Lovelace');

        const phoneEls = contactEls[0].querySelectorAll(
            'ul.slds-var-m-around_medium > li'
        );
        expect(phoneEls.length).toBe(2);
        expect(phoneEls[0].textContent).toContain('555-0100');
        expect(phoneEls[0].textContent).toContain('(mobile)');
        expect(element.shadowRoot.querySelector('c-error-panel')).toBeNull();
        expect(
            element.shadowRoot.querySelector('lightning-spinner')
        ).toBeNull();
    });

    it('renders a spinner while contacts are loading', async () => {
        setContactsServiceAvailable(true);
        getContactsService.mockImplementationOnce(() => ({
            isAvailable: () => true,
            getContacts: () => new Promise(() => {})
        }));

        const element = createComponent();

        await flushPromises();

        expect(
            element.shadowRoot.querySelector('lightning-spinner')
        ).not.toBeNull();
        expect(element.shadowRoot.querySelector('c-error-panel')).toBeNull();
    });

    it('renders an error panel when retrieving contacts fails', async () => {
        const error = { message: 'Permission denied' };
        setContactsServiceAvailable(true);
        setContactsServiceError(error);

        const element = createComponent();

        await flushPromises();
        await flushPromises();

        const panelEl = element.shadowRoot.querySelector('c-error-panel');
        expect(panelEl).not.toBeNull();
        expect(panelEl.errors).toEqual(error);
    });

    it('is accessible when contacts are displayed', async () => {
        setContactsServiceAvailable(true);
        setContactsServiceContacts(MOCK_CONTACTS);

        const element = createComponent();

        await flushPromises();
        await flushPromises();

        await expect(element).toBeAccessible();
    });

    it('is accessible when the contacts service is not available', async () => {
        const element = createComponent();

        await flushPromises();

        await expect(element).toBeAccessible();
    });
});
