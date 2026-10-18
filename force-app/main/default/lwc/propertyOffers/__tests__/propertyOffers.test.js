import { createElement } from '@lwc/engine-dom';
import PropertyOffers from 'c/propertyOffers';
import { getRecord } from 'lightning/uiRecordApi';
import { ShowToastEventName } from 'lightning/platformShowToastEvent';
import getOffers from '@salesforce/apex/OfferController.getOffers';
import canApproveOffers from '@salesforce/apex/OfferController.canApproveOffers';
import submitOffer from '@salesforce/apex/OfferController.submitOffer';
import acceptOffer from '@salesforce/apex/OfferController.acceptOffer';

const mockOffers = require('./data/getOffers.json');
const mockProperty = require('./data/getPropertyRecord.json');

jest.mock(
    '@salesforce/apex/OfferController.getOffers',
    () => {
        const {
            createApexTestWireAdapter
        } = require('@salesforce/sfdx-lwc-jest');
        return { default: createApexTestWireAdapter(jest.fn()) };
    },
    { virtual: true }
);
jest.mock(
    '@salesforce/apex/OfferController.canApproveOffers',
    () => {
        const {
            createApexTestWireAdapter
        } = require('@salesforce/sfdx-lwc-jest');
        return { default: createApexTestWireAdapter(jest.fn()) };
    },
    { virtual: true }
);
jest.mock(
    '@salesforce/apex/OfferController.submitOffer',
    () => ({ default: jest.fn() }),
    { virtual: true }
);
jest.mock(
    '@salesforce/apex/OfferController.approveOffer',
    () => ({ default: jest.fn() }),
    { virtual: true }
);
jest.mock(
    '@salesforce/apex/OfferController.acceptOffer',
    () => ({ default: jest.fn() }),
    { virtual: true }
);
jest.mock(
    '@salesforce/apex/OfferController.rejectOffer',
    () => ({ default: jest.fn() }),
    { virtual: true }
);

async function flushPromises() {
    return Promise.resolve();
}

function createComponent() {
    const element = createElement('c-property-offers', { is: PropertyOffers });
    element.recordId = mockProperty.id;
    document.body.appendChild(element);
    return element;
}

describe('c-property-offers', () => {
    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
        jest.clearAllMocks();
    });

    it('shows the empty state when there are no offers', async () => {
        const element = createComponent();
        getRecord.emit(mockProperty);
        getOffers.emit([]);
        await flushPromises();

        expect(element.shadowRoot.querySelector('.no-offers')).not.toBeNull();
        expect(element.shadowRoot.querySelector('lightning-card').title).toBe(
            'Offers (0)'
        );
    });

    it('renders offers with status-based actions', async () => {
        const element = createComponent();
        getRecord.emit(mockProperty);
        canApproveOffers.emit(false);
        getOffers.emit(mockOffers);
        await flushPromises();

        const items = element.shadowRoot.querySelectorAll('.offer');
        expect(items.length).toBe(2);
        expect(element.shadowRoot.querySelector('lightning-card').title).toBe(
            'Offers (2)'
        );
        // Needs Approval offer: no Accept, no Approve without permission
        expect(items[0].querySelector('.accept')).toBeNull();
        expect(items[0].querySelector('.approve')).toBeNull();
        expect(items[0].querySelector('.reject')).not.toBeNull();
        // Submitted offer: can be accepted
        expect(items[1].querySelector('.accept')).not.toBeNull();
    });

    it('shows Approve for brokers with the Approve Offers permission', async () => {
        const element = createComponent();
        getRecord.emit(mockProperty);
        canApproveOffers.emit(true);
        getOffers.emit(mockOffers);
        await flushPromises();

        const items = element.shadowRoot.querySelectorAll('.offer');
        expect(items[0].querySelector('.approve')).not.toBeNull();
    });

    it('previews the discount and flags offers needing approval', async () => {
        const element = createComponent();
        getRecord.emit(mockProperty);
        getOffers.emit([]);
        await flushPromises();

        const amountInput =
            element.shadowRoot.querySelectorAll('lightning-input')[1];
        amountInput.value = 700000;
        amountInput.dispatchEvent(new CustomEvent('change'));
        await flushPromises();

        const preview = element.shadowRoot.querySelector('.preview');
        expect(preview.textContent).toContain('17.2% below asking');
        expect(preview.textContent).toContain('needs broker approval');

        amountInput.value = 820000;
        amountInput.dispatchEvent(new CustomEvent('change'));
        await flushPromises();
        expect(
            element.shadowRoot.querySelector('.preview').textContent
        ).not.toContain('needs broker approval');
    });

    it('rounds like Apex at the approval threshold', async () => {
        const element = createComponent();
        getRecord.emit(mockProperty);
        getOffers.emit([]);
        await flushPromises();

        // 10.04% below asking rounds to 10.0%, which does not need approval.
        const amountInput =
            element.shadowRoot.querySelectorAll('lightning-input')[1];
        amountInput.value = 760162;
        amountInput.dispatchEvent(new CustomEvent('change'));
        await flushPromises();

        const preview = element.shadowRoot.querySelector('.preview');
        expect(preview.textContent).toContain('10.0% below asking');
        expect(preview.textContent).not.toContain('needs broker approval');
    });

    it('submits an offer and shows a warning toast when approval is needed', async () => {
        submitOffer.mockResolvedValue({ Status__c: 'Needs Approval' });
        const element = createComponent();
        const toastHandler = jest.fn();
        element.addEventListener(ShowToastEventName, toastHandler);
        getRecord.emit(mockProperty);
        getOffers.emit([]);
        await flushPromises();

        const [buyerInput, amountInput] =
            element.shadowRoot.querySelectorAll('lightning-input');
        buyerInput.value = 'Sam Lowball';
        buyerInput.dispatchEvent(new CustomEvent('change'));
        amountInput.value = 700000;
        amountInput.dispatchEvent(new CustomEvent('change'));
        buyerInput.reportValidity = jest.fn(() => true);
        amountInput.reportValidity = jest.fn(() => true);

        element.shadowRoot.querySelector('.submit').click();
        await flushPromises();
        await flushPromises();

        expect(submitOffer).toHaveBeenCalledWith({
            propertyId: mockProperty.id,
            buyerName: 'Sam Lowball',
            amount: 700000
        });
        expect(toastHandler).toHaveBeenCalled();
        expect(toastHandler.mock.calls[0][0].detail.variant).toBe('warning');
    });

    it('accepts an offer', async () => {
        acceptOffer.mockResolvedValue({ Status__c: 'Accepted' });
        const element = createComponent();
        getRecord.emit(mockProperty);
        canApproveOffers.emit(false);
        getOffers.emit(mockOffers);
        await flushPromises();

        element.shadowRoot
            .querySelectorAll('.offer')[1]
            .querySelector('.accept')
            .click();
        await flushPromises();

        expect(acceptOffer).toHaveBeenCalledWith({
            offerId: mockOffers[1].Id
        });
    });

    it('disables submission on a closed property', async () => {
        const element = createComponent();
        getRecord.emit({
            ...mockProperty,
            fields: {
                ...mockProperty.fields,
                Status__c: { value: 'Closed', displayValue: 'Closed' }
            }
        });
        getOffers.emit([]);
        await flushPromises();

        expect(element.shadowRoot.querySelector('.submit').disabled).toBe(true);
    });

    it('is accessible', async () => {
        const element = createComponent();
        getRecord.emit(mockProperty);
        canApproveOffers.emit(true);
        getOffers.emit(mockOffers);
        await flushPromises();

        await expect(element).toBeAccessible();
    });
});
