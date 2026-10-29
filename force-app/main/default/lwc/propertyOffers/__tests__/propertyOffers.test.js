import { createElement } from '@lwc/engine-dom';
import PropertyOffers from 'c/propertyOffers';
import { getRecord, notifyRecordUpdateAvailable } from 'lightning/uiRecordApi';
import { ShowToastEventName } from 'lightning/platformShowToastEvent';
import getOfferContext from '@salesforce/apex/OfferController.getOfferContext';
import submitOffer from '@salesforce/apex/OfferController.submitOffer';
import approveOffer from '@salesforce/apex/OfferController.approveOffer';
import acceptOffer from '@salesforce/apex/OfferController.acceptOffer';
import rejectOffer from '@salesforce/apex/OfferController.rejectOffer';
import { percentBelowAsking, needsApproval } from '../offerMath';

jest.mock(
    '@salesforce/apex/OfferController.getOfferContext',
    () => ({ default: jest.fn() }),
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

const PROPERTY_ID = 'a0Vaj00000ec4VAEAY';
const JANE = {
    Id: 'a0Oaj0000000001',
    Buyer_Name__c: 'Jane Buyer',
    Amount__c: 820000,
    Percent_Below_Asking__c: 3.0,
    Status__c: 'Submitted'
};
const SAM = {
    Id: 'a0Oaj0000000002',
    Buyer_Name__c: 'Sam Lowball',
    Amount__c: 720000,
    Percent_Below_Asking__c: 14.8,
    Status__c: 'Needs Approval'
};

function context(overrides = {}) {
    return {
        askingPrice: 845000,
        propertyStatus: 'Available',
        acceptingOffers: true,
        canApprove: true,
        offers: [],
        ...overrides
    };
}

async function flushPromises() {
    for (let i = 0; i < 5; i++) {
        // eslint-disable-next-line no-await-in-loop
        await Promise.resolve();
    }
}

function createComponent(recordId = PROPERTY_ID) {
    const element = createElement('c-property-offers', { is: PropertyOffers });
    element.recordId = recordId;
    document.body.appendChild(element);
    return element;
}

function input(element, label) {
    return [...element.shadowRoot.querySelectorAll('lightning-input')].find(
        (el) => el.label === label
    );
}

function buttonByTitle(element, title) {
    return element.shadowRoot.querySelector(
        `lightning-button[title="${title}"]`
    );
}

function submitButton(element) {
    return [...element.shadowRoot.querySelectorAll('lightning-button')].find(
        (el) => el.label === 'Submit offer'
    );
}

async function type(element, label, value) {
    const el = input(element, label);
    el.value = value;
    el.dispatchEvent(new CustomEvent('change'));
    await flushPromises();
}

describe('offerMath', () => {
    it('rounds half-up to one decimal like Apex', () => {
        expect(percentBelowAsking(845000, 720000)).toBe(14.8);
        expect(percentBelowAsking(845000, 820000)).toBe(3.0);
        expect(percentBelowAsking(100000, 89950)).toBe(10.1);
        expect(percentBelowAsking(100000, 89951)).toBe(10.0);
        expect(percentBelowAsking(100000, 105000)).toBe(-5.0);
        expect(percentBelowAsking(100000, 100000)).toBe(0);
    });

    it('returns null when it cannot compute', () => {
        expect(percentBelowAsking(null, 1)).toBeNull();
        expect(percentBelowAsking(0, 1)).toBeNull();
        expect(percentBelowAsking(100, '')).toBeNull();
        expect(percentBelowAsking(100, 'abc')).toBeNull();
    });

    it('needs approval only above 10%', () => {
        expect(needsApproval(10.1)).toBe(true);
        expect(needsApproval(10.0)).toBe(false);
        expect(needsApproval(null)).toBe(false);
    });
});

describe('c-property-offers', () => {
    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
        jest.clearAllMocks();
    });

    it('renders an empty Offers card', async () => {
        getOfferContext.mockResolvedValue(context());
        const element = createComponent();
        await flushPromises();

        expect(getOfferContext).toHaveBeenCalledWith({
            propertyId: PROPERTY_ID
        });
        const card = element.shadowRoot.querySelector('lightning-card');
        expect(card.title).toBe('Offers (0)');
        expect(element.shadowRoot.querySelector('.empty')).not.toBeNull();
        expect(submitButton(element).disabled).toBe(true);
        await expect(element).toBeAccessible();
    });

    it('previews % below asking and warns when approval is needed', async () => {
        getOfferContext.mockResolvedValue(context());
        const element = createComponent();
        await flushPromises();

        await type(element, 'Offer amount', 820000);
        let preview = element.shadowRoot.querySelector('[data-id="preview"]');
        expect(preview.textContent).toContain('3.0% below asking');
        expect(preview.textContent).not.toContain('needs broker approval');

        await type(element, 'Offer amount', 720000);
        preview = element.shadowRoot.querySelector('[data-id="preview"]');
        expect(preview.textContent).toContain(
            '14.8% below asking, needs broker approval'
        );

        await type(element, 'Offer amount', 900000);
        preview = element.shadowRoot.querySelector('[data-id="preview"]');
        expect(preview.textContent).toContain('6.5% above asking');
    });

    it('submits an offer, clears the form and reloads', async () => {
        getOfferContext
            .mockResolvedValueOnce(context())
            .mockResolvedValueOnce(context({ offers: [SAM] }));
        submitOffer.mockResolvedValue(SAM);
        const element = createComponent();
        const toastHandler = jest.fn();
        element.addEventListener(ShowToastEventName, toastHandler);
        await flushPromises();

        await type(element, 'Buyer name', 'Sam Lowball');
        await type(element, 'Offer amount', 720000);
        expect(submitButton(element).disabled).toBe(false);
        submitButton(element).click();
        await flushPromises();

        expect(submitOffer).toHaveBeenCalledWith({
            propertyId: PROPERTY_ID,
            buyerName: 'Sam Lowball',
            amount: 720000
        });
        expect(toastHandler.mock.calls[0][0].detail.variant).toBe('warning');
        expect(input(element, 'Buyer name').value).toBe('');
        expect(element.shadowRoot.querySelector('lightning-card').title).toBe(
            'Offers (1)'
        );
    });

    it('shows an error toast when submit fails', async () => {
        getOfferContext.mockResolvedValue(context());
        submitOffer.mockRejectedValue({
            body: { message: 'Offer amount must be greater than zero.' }
        });
        const element = createComponent();
        const toastHandler = jest.fn();
        element.addEventListener(ShowToastEventName, toastHandler);
        await flushPromises();

        await type(element, 'Buyer name', 'Jane');
        await type(element, 'Offer amount', 5);
        submitButton(element).click();
        await flushPromises();

        const detail = toastHandler.mock.calls[0][0].detail;
        expect(detail.variant).toBe('error');
        expect(detail.message).toBe('Offer amount must be greater than zero.');
    });

    it('shows status badges and the right buttons per offer', async () => {
        getOfferContext.mockResolvedValue(context({ offers: [SAM, JANE] }));
        const element = createComponent();
        await flushPromises();

        const badges = [...element.shadowRoot.querySelectorAll('.slds-badge')];
        expect(badges.map((b) => b.textContent.trim())).toEqual([
            'Needs Approval',
            'Submitted'
        ]);
        expect(
            buttonByTitle(element, 'Approve offer from Sam Lowball')
        ).not.toBeNull();
        expect(
            buttonByTitle(element, 'Accept offer from Sam Lowball')
        ).toBeNull();
        expect(
            buttonByTitle(element, 'Accept offer from Jane Buyer')
        ).not.toBeNull();
        expect(
            buttonByTitle(element, 'Approve offer from Jane Buyer')
        ).toBeNull();
        expect(
            buttonByTitle(element, 'Reject offer from Sam Lowball')
        ).not.toBeNull();
    });

    it('hides Approve from users without the permission', async () => {
        getOfferContext.mockResolvedValue(
            context({ canApprove: false, offers: [SAM] })
        );
        const element = createComponent();
        await flushPromises();

        expect(
            buttonByTitle(element, 'Approve offer from Sam Lowball')
        ).toBeNull();
        expect(
            buttonByTitle(element, 'Reject offer from Sam Lowball')
        ).not.toBeNull();
    });

    it('asks for re-approval when the server flags an approved offer', async () => {
        const approved = { ...SAM, Status__c: 'Approved' };
        getOfferContext.mockResolvedValue(
            context({
                offers: [approved],
                approvalRequiredOfferIds: [approved.Id]
            })
        );
        const element = createComponent();
        await flushPromises();

        expect(
            buttonByTitle(element, 'Approve offer from Sam Lowball')
        ).not.toBeNull();
        expect(
            buttonByTitle(element, 'Accept offer from Sam Lowball')
        ).toBeNull();
    });

    it('approves, then accepts and refreshes the property record', async () => {
        const approved = { ...SAM, Status__c: 'Approved' };
        const accepted = { ...SAM, Status__c: 'Accepted' };
        getOfferContext
            .mockResolvedValueOnce(context({ offers: [SAM, JANE] }))
            .mockResolvedValueOnce(context({ offers: [approved, JANE] }))
            .mockResolvedValueOnce(
                context({
                    propertyStatus: 'Under Agreement',
                    acceptingOffers: false,
                    offers: [accepted, { ...JANE, Status__c: 'Rejected' }]
                })
            );
        approveOffer.mockResolvedValue(approved);
        acceptOffer.mockResolvedValue(accepted);
        const element = createComponent();
        await flushPromises();

        buttonByTitle(element, 'Approve offer from Sam Lowball').click();
        await flushPromises();
        expect(approveOffer).toHaveBeenCalledWith({ offerId: SAM.Id });

        buttonByTitle(element, 'Accept offer from Sam Lowball').click();
        await flushPromises();
        expect(acceptOffer).toHaveBeenCalledWith({ offerId: SAM.Id });
        expect(notifyRecordUpdateAvailable).toHaveBeenCalledWith([
            { recordId: PROPERTY_ID }
        ]);

        const badges = [...element.shadowRoot.querySelectorAll('.slds-badge')];
        expect(badges.map((b) => b.textContent.trim())).toEqual([
            'Accepted',
            'Rejected'
        ]);
        expect(element.shadowRoot.querySelector('.offer-form')).toBeNull();
        expect(
            element.shadowRoot.querySelector('.closed-message').textContent
        ).toContain('Under Agreement');
        expect(
            element.shadowRoot.querySelectorAll('lightning-button').length
        ).toBe(0);
    });

    it('rejects an offer', async () => {
        getOfferContext.mockResolvedValue(context({ offers: [JANE] }));
        rejectOffer.mockResolvedValue({ ...JANE, Status__c: 'Rejected' });
        const element = createComponent();
        await flushPromises();

        buttonByTitle(element, 'Reject offer from Jane Buyer').click();
        await flushPromises();
        expect(rejectOffer).toHaveBeenCalledWith({ offerId: JANE.Id });
        expect(notifyRecordUpdateAvailable).not.toHaveBeenCalled();
    });

    it('shows an error toast and reloads when an action fails', async () => {
        getOfferContext.mockResolvedValue(context({ offers: [JANE] }));
        acceptOffer.mockRejectedValue({
            body: { message: 'This property is Closed.' }
        });
        const element = createComponent();
        const toastHandler = jest.fn();
        element.addEventListener(ShowToastEventName, toastHandler);
        await flushPromises();

        buttonByTitle(element, 'Accept offer from Jane Buyer').click();
        await flushPromises();
        expect(toastHandler.mock.calls[0][0].detail.message).toBe(
            'This property is Closed.'
        );
        expect(getOfferContext).toHaveBeenCalledTimes(2);
    });

    it('shows load errors', async () => {
        getOfferContext.mockRejectedValue({
            body: { message: 'Property not found.' }
        });
        const element = createComponent();
        await flushPromises();
        expect(element.shadowRoot.textContent).toContain('Property not found.');
    });

    it('resets the form and drops stale responses when recordId changes', async () => {
        let resolveFirst;
        getOfferContext
            .mockResolvedValueOnce(context())
            .mockImplementationOnce(
                () =>
                    new Promise((resolve) => {
                        resolveFirst = resolve;
                    })
            )
            .mockResolvedValueOnce(
                context({ askingPrice: 500000, offers: [JANE] })
            );
        const element = createComponent();
        await flushPromises();
        await type(element, 'Buyer name', 'Typed Buyer');

        element.recordId = 'a0Vaj00000000002';
        element.recordId = 'a0Vaj00000000003';
        await flushPromises();
        resolveFirst(context({ offers: [SAM, JANE] }));
        await flushPromises();

        expect(input(element, 'Buyer name').value).toBe('');
        expect(element.shadowRoot.querySelector('lightning-card').title).toBe(
            'Offers (1)'
        );
    });

    it('reloads when the asking price changes on the record', async () => {
        getOfferContext.mockResolvedValue(context());
        createComponent();
        await flushPromises();

        getRecord.emit({
            fields: {
                Price__c: { value: 845000 },
                Status__c: { value: 'Available' }
            }
        });
        await flushPromises();
        expect(getOfferContext).toHaveBeenCalledTimes(1);

        getRecord.emit({
            fields: {
                Price__c: { value: 900000 },
                Status__c: { value: 'Available' }
            }
        });
        await flushPromises();
        expect(getOfferContext).toHaveBeenCalledTimes(2);
    });
});
