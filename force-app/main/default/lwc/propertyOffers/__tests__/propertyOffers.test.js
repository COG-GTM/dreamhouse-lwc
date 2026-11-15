import { createElement } from '@lwc/engine-dom';
import PropertyOffers from 'c/propertyOffers';
import { refreshApex } from '@salesforce/apex';
import { notifyRecordUpdateAvailable } from 'lightning/uiRecordApi';
import { ShowToastEventName } from 'lightning/platformShowToastEvent';
import getOffers from '@salesforce/apex/PropertyOffersController.getOffers';
import submitOffer from '@salesforce/apex/PropertyOffersController.submitOffer';
import approveOffer from '@salesforce/apex/PropertyOffersController.approveOffer';
import acceptOffer from '@salesforce/apex/PropertyOffersController.acceptOffer';
import rejectOffer from '@salesforce/apex/PropertyOffersController.rejectOffer';

jest.mock(
    '@salesforce/apex/PropertyOffersController.getOffers',
    () => {
        const {
            createApexTestWireAdapter
        } = require('@salesforce/sfdx-lwc-jest');
        return { default: createApexTestWireAdapter(jest.fn()) };
    },
    { virtual: true }
);
jest.mock(
    '@salesforce/apex/PropertyOffersController.submitOffer',
    () => ({ default: jest.fn() }),
    { virtual: true }
);
jest.mock(
    '@salesforce/apex/PropertyOffersController.approveOffer',
    () => ({ default: jest.fn() }),
    { virtual: true }
);
jest.mock(
    '@salesforce/apex/PropertyOffersController.acceptOffer',
    () => ({ default: jest.fn() }),
    { virtual: true }
);
jest.mock(
    '@salesforce/apex/PropertyOffersController.rejectOffer',
    () => ({ default: jest.fn() }),
    { virtual: true }
);

const flush = async () => {
    await Promise.resolve();
    await Promise.resolve();
    await Promise.resolve();
    await Promise.resolve();
    await Promise.resolve();
    await Promise.resolve();
    await Promise.resolve();
    await Promise.resolve();
};
const offer = (status, id = 'offer1') => ({
    Id: id,
    Buyer_Name__c: 'Alex Buyer',
    Amount__c: 720000,
    Percent_Below_Asking__c: 14.8,
    Status__c: status
});
const data = (
    offers = [],
    canApprove = false,
    propertyStatus = 'Available'
) => ({
    offers,
    canApprove,
    propertyStatus,
    askingPrice: 845000
});
async function mount(value = data()) {
    const element = createElement('c-property-offers', { is: PropertyOffers });
    element.recordId = 'property1';
    document.body.appendChild(element);
    getOffers.emit(value);
    await flush();
    return element;
}
function button(element, label) {
    return [...element.shadowRoot.querySelectorAll('lightning-button')].find(
        (item) => item.label === label
    );
}
function input(element, label, value) {
    const field = [
        ...element.shadowRoot.querySelectorAll('lightning-input')
    ].find((item) => item.label === label);
    field.value = value;
    field.dispatchEvent(new CustomEvent('change'));
}
function validInputs(element, valid = true) {
    element.shadowRoot.querySelectorAll('lightning-input').forEach((field) => {
        field.reportValidity = jest.fn(() => valid);
    });
}
describe('c-property-offers', () => {
    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
        jest.clearAllMocks();
    });
    it('renders an empty card and the exact input labels', async () => {
        const element = await mount();
        expect(element.shadowRoot.querySelector('lightning-card').title).toBe(
            'Offers (0)'
        );
        expect(element.shadowRoot.textContent).toContain('No offers yet.');
        expect(
            [...element.shadowRoot.querySelectorAll('lightning-input')].map(
                (field) => field.label
            )
        ).toEqual(['Buyer name', 'Offer amount']);
        expect(getOffers.getLastConfig()).toEqual({ propertyId: 'property1' });
    });
    it.each([
        [720000, '14.8% below asking, needs broker approval'],
        [760162, '10.0% below asking'],
        [760077.5, '10.1% below asking, needs broker approval'],
        [929922.5, '-10.1% below asking'],
        [0, ''],
        ['', '']
    ])(
        'previews amount %s using rounded approval threshold',
        async (amount, expected) => {
            const element = await mount();
            input(element, 'Offer amount', amount);
            await flush();
            expect(
                element.shadowRoot.querySelector('[aria-live]').textContent
            ).toBe(expected);
        }
    );
    it('does not preview a missing or zero asking price', async () => {
        const element = await mount({ ...data(), askingPrice: 0 });
        input(element, 'Offer amount', 100);
        await flush();
        expect(
            element.shadowRoot.querySelector('[aria-live]').textContent
        ).toBe('');
    });
    it('submits, clears inputs and refreshes the list', async () => {
        submitOffer.mockResolvedValue('newOffer');
        const element = await mount();
        validInputs(element);
        input(element, 'Buyer name', 'Taylor');
        input(element, 'Offer amount', '720000');
        button(element, 'Submit').click();
        await flush();
        expect(submitOffer).toHaveBeenCalledWith({
            propertyId: 'property1',
            buyerName: 'Taylor',
            amount: 720000
        });
        expect(refreshApex).toHaveBeenCalled();
        expect(
            [...element.shadowRoot.querySelectorAll('lightning-input')].map(
                (field) => field.value
            )
        ).toEqual(['', '']);
        expect(button(element, 'Submit').disabled).toBe(false);
    });
    it('blocks invalid form values', async () => {
        const element = await mount();
        validInputs(element, false);
        button(element, 'Submit').click();
        await flush();
        expect(submitOffer).not.toHaveBeenCalled();
    });
    it.each(['Closed', 'Under Agreement'])(
        'disables submission on %s properties',
        async (status) => {
            const element = await mount(data([], false, status));
            expect(button(element, 'Submit').disabled).toBe(true);
            expect(element.shadowRoot.textContent).toContain(
                'no longer available'
            );
        }
    );
    it.each([
        ['Submitted', false, ['Accept', 'Reject']],
        ['Needs Approval', false, ['Reject']],
        ['Needs Approval', true, ['Approve', 'Reject']],
        ['Approved', true, ['Accept', 'Reject']],
        ['Accepted', true, []],
        ['Rejected', true, []]
    ])(
        'renders appropriate actions for %s (broker=%s)',
        async (status, broker, actions) => {
            const element = await mount(data([offer(status)], broker));
            expect(
                element.shadowRoot.querySelector('lightning-card').title
            ).toBe('Offers (1)');
            expect(
                element.shadowRoot.querySelector('lightning-badge').label
            ).toBe(status);
            expect(
                [
                    ...element.shadowRoot.querySelectorAll(
                        'li lightning-button'
                    )
                ].map((item) => item.label)
            ).toEqual(actions);
        }
    );
    it.each([
        ['Approve', 'Needs Approval', approveOffer],
        ['Accept', 'Submitted', acceptOffer],
        ['Reject', 'Approved', rejectOffer]
    ])('runs %s and refreshes', async (label, status, action) => {
        action.mockResolvedValue(undefined);
        const element = await mount(data([offer(status)], true));
        button(element, label).click();
        await flush();
        expect(action).toHaveBeenCalledWith({ offerId: 'offer1' });
        expect(refreshApex).toHaveBeenCalled();
        expect(notifyRecordUpdateAvailable.mock.calls).toEqual(
            label === 'Accept' ? [[[{ recordId: 'property1' }]]] : []
        );
    });
    it('toasts submission errors and preserves form values', async () => {
        submitOffer.mockRejectedValue({ body: { message: 'Not available' } });
        const element = await mount();
        const toast = jest.fn();
        element.addEventListener(ShowToastEventName, toast);
        validInputs(element);
        input(element, 'Buyer name', 'Taylor');
        input(element, 'Offer amount', '720000');
        button(element, 'Submit').click();
        await flush();
        expect(toast.mock.calls[0][0].detail).toMatchObject({
            message: 'Not available',
            variant: 'error'
        });
        expect(element.shadowRoot.querySelector('lightning-input').value).toBe(
            'Taylor'
        );
        expect(button(element, 'Submit').disabled).toBe(false);
    });
    it.each([
        ['Approve', 'Needs Approval', approveOffer],
        ['Accept', 'Submitted', acceptOffer],
        ['Reject', 'Approved', rejectOffer]
    ])('toasts %s errors', async (label, status, action) => {
        action.mockRejectedValue(new Error('Action denied'));
        const element = await mount(data([offer(status)], true));
        const toast = jest.fn();
        element.addEventListener(ShowToastEventName, toast);
        button(element, label).click();
        await flush();
        expect(toast.mock.calls[0][0].detail.message).toBe('Action denied');
        expect(refreshApex).not.toHaveBeenCalled();
    });
    it('toasts load errors', async () => {
        const element = await mount();
        const toast = jest.fn();
        element.addEventListener(ShowToastEventName, toast);
        getOffers.error({ message: 'Read denied' });
        await flush();
        expect(toast.mock.calls[0][0].detail.message).toBe('Read denied');
    });
});
